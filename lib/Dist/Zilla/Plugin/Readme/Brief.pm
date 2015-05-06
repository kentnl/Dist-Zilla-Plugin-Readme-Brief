use 5.010;    # m regexp propagation
use strict;
use warnings;

package Dist::Zilla::Plugin::Readme::Brief;

our $VERSION = '0.002006';

# ABSTRACT: Provide a short simple README with just the essentials

our $AUTHORITY = 'cpan:KENTNL'; # AUTHORITY

use Moose qw( with has around );
use List::Util qw( first );
use MooseX::Types::Moose qw( ArrayRef Str );
use Moose::Util::TypeConstraints qw( enum );
use Dist::Zilla::Util::ConfigDumper qw( config_dumper );
use PPIx::DocumentName;

with 'Dist::Zilla::Role::PPI';
with 'Dist::Zilla::Role::FileGatherer';

my %installers = (
  'eumm' => '_install_eumm',
  'mb'   => '_install_mb',
);























has 'installer' => (
  isa => ArrayRef [ enum( [ keys %installers ] ) ],
  is => 'ro',
  traits    => ['Array'],
  predicate => 'has_installer',
  handles   => {
    '_installers' => 'elements',
  },
);

no Moose::Util::TypeConstraints;

has 'description_label' => (
  isa     => Str,
  is      => 'ro',
  lazy    => 1,
  default => sub { 'DESCRIPTION' },
);

around 'mvp_multivalue_args' => sub {
  my ( $orig, $self, @rest ) = @_;
  return ( $self->$orig(@rest), 'installer' );
};

around 'mvp_aliases' => sub {
  my ( $orig, $self, @rest ) = @_;
  return { %{ $self->$orig(@rest) }, installers => 'installer' };
};

around dump_config => config_dumper( __PACKAGE__, { attrs => ['installer'] } );

__PACKAGE__->meta->make_immutable;
no Moose;





sub gather_files {
  my ($self) = @_;
  require Dist::Zilla::File::FromCode;
  $self->add_file(
    Dist::Zilla::File::FromCode->new(
      name => 'README',
      code => sub {
        return $self->_generate_content;
      },
    ),
  );
  return;
}

# Internal Methods

sub _generate_content {
  my ($self) = @_;

  # each section should end with exactly one trailing newline
  return join qq[\n], $self->_description_section, $self->_installer_section, $self->_copyright_section;
}

sub _description_section {
  my ($self) = @_;
  return $self->_heading . qq[\n\n] . $self->_description . qq[\n];
}

sub _installer_section {
  my ($self) = @_;
  my $out = q[];
  $out .= qq[INSTALLATION\n\n];
  $out .= $self->_install_auto;

  my $manual_instructions = ( $self->has_installer ) ? $self->_configured_installer : $self->_auto_installer;

  if ( defined $manual_instructions ) {
    $out .= "Should you wish to install this module manually, the procedure is\n\n";
    $out .= $manual_instructions;
  }
  else {
    $self->log('No install method detected. Omitting Manual Installation Instructions');
  }
  return $out;
}

sub _copyright_section {
  my ($self) = @_;
  if ( my $copy = $self->_copyright_from_pod ) {
    return $copy . qq[\n];
  }
  return $self->_copyright_from_dist;
}

sub _auto_installer {
  my ($self) = @_;
  $self->log_debug('Autodetecting installer');
  if ( first { $_->name =~ /\AMakefile.PL\z/msx } @{ $self->zilla->files } ) {
    return $self->_install_eumm;
  }
  elsif ( first { $_->name =~ /\ABuild.PL\z/msx } @{ $self->zilla->files } ) {
    return $self->_install_mb;
  }
  return;
}

sub _configured_installer {
  my ($self) = @_;
  $self->log_debug('Using configured installer');

  my @sections;
  for my $installer ( $self->_installers ) {
    my $method = $installers{$installer};
    push @sections, $self->$method();
  }
  return unless @sections;
  return join qq[\nor\n\n], @sections;
}

sub _source_pm_file {
  my ($self) = @_;
  return $self->zilla->main_module;
}

sub _source_pod {
  my ($self) = @_;
  return $self->{_pod_cache} if exists $self->{_pod_cache};
  my $chars = $self->_source_pm_file->content;

  require Encode;
  require Pod::Elemental;
  require Pod::Elemental::Transformer::Pod5;
  require Pod::Elemental::Transformer::Nester;
  require Pod::Elemental::Selectors;

  my $octets = Encode::encode( 'UTF-8', $chars, Encode::FB_CROAK() );
  my $document = Pod::Elemental->read_string($octets);
  Pod::Elemental::Transformer::Pod5->new->transform_node($document);

  my $nester = Pod::Elemental::Transformer::Nester->new(
    {
      top_selector => Pod::Elemental::Selectors::s_command('head1'),
      content_selectors =>
        [ Pod::Elemental::Selectors::s_flat(), Pod::Elemental::Selectors::s_command( [qw(head2 head3 head4 over item back)] ), ],
    },
  );
  $nester->transform_node($document);

  $self->{_pod_cache} = $document;
  return $document;
}

sub _podtext_nodes {
  my ( undef, @nodes ) = @_;
  require Pod::Text;
  my $parser = Pod::Text->new( loose => 1 );
  $parser->output_string( \( my $text ) );
  $parser->parse_string_document( join qq[\n], '=pod', q[], map { $_->as_pod_string } @nodes );

  # strip extra indent;
  $text =~ s{^[ ]{4}}{}msxg;
  $text =~ s{\n+\z}{}msx;
  return $text;
}

sub _heading {
  my ($self) = @_;
  require PPI::Document;    # Historic version of dzil doesn't load PPI on its own...
  my $document = $self->ppi_document_for_file( $self->_source_pm_file );
  return PPIx::DocumentName->extract($document);
}

sub _description {
  my ($self)  = @_;
  my $pod     = $self->_source_pod;
  my (@nodes) = @{ $pod->children };

  my @found;

  require Pod::Elemental::Selectors;

  for my $node_number ( 0 .. $#nodes ) {
    next unless Pod::Elemental::Selectors::s_command( head1 => $nodes[$node_number] );
    next unless $self->description_label eq uc $nodes[$node_number]->content;
    push @found, $nodes[$node_number];
  }
  if ( not @found ) {
    $self->log( $self->description_label . ' not found in ' . $self->_source_pm_file->name );
    return q[];
  }
  return $self->_podtext_nodes( map { @{ $_->children } } @found );
}

sub _copyright_from_dist {

  # Construct a copyright even if the POD doesn't have one
  my ($self) = @_;
  my $notice = $self->zilla->license->notice;
  return qq[COPYRIGHT AND LICENSE\n\n$notice];
}

sub _copyright_from_pod {
  my ($self)  = @_;
  my $pod     = $self->_source_pod;
  my (@nodes) = @{ $pod->children };

  my @found;

  require Pod::Elemental::Selectors;

  for my $node_number ( 0 .. $#nodes ) {
    next unless Pod::Elemental::Selectors::s_command( head1 => $nodes[$node_number] );
    next unless $nodes[$node_number]->content =~ /COPYRIGHT|LICENSE/imsx;
    push @found, $nodes[$node_number];
  }
  if ( not @found ) {
    $self->log( 'COPYRIGHT/LICENSE not found in ' . $self->_source_pm_file->name );
    return;
  }
  return $self->_podtext_nodes(@found);
}

sub _install_auto {
  return <<"EOFAUTO";
This is a Perl module distribution. It should be installed with whichever
tool you use to manage your installation of Perl, e.g. any of

  cpanm .
  cpan  .
  cpanp -i .

Consult http://www.cpan.org/modules/INSTALL.html for further instruction.
EOFAUTO
}

sub _install_eumm {
  return <<"EOFEUMM";
  perl Makefile.PL
  make
  make test
  make install
EOFEUMM
}

sub _install_mb {
  return <<"EOFMB";
  perl Build.PL
  ./Build
  ./Build test
  ./Build install
EOFMB
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Readme::Brief - Provide a short simple README with just the essentials

=head1 VERSION

version 0.002006

=head1 SYNOPSIS

  [Readme::Brief]
  ; Override autodetected install method
  installer = eumm
  ; Override name to use for brief body
  description_label = WHAT IS THIS

=head1 DESCRIPTION

This provides a terse but informative README file for your CPAN distribution
that contains just the essential details about your dist a casual consumer would want to know.

=over 4

=item * The name of the primary module in the distribution

=item * The distribution's main modules description

=item * Simple installation instructions from an extracted archive

=item * Short copyright information

=back

=head1 NOTE

This is still reasonably fresh code and reasonably experimental, and feature enhancements and bug fixes
are actively desired.

However, bugs are highly likely to be encountered, especially as there are no tests.

=head1 MECHANICS

=over 4

=item * Heading is derived from the C<package> statement in C<main_module>

=item * Description is extracted as the entire C<H1Nest> of the section titled C<DESCRIPTION> ( or whatever C<description_label> is ) in C<main_module>

=item * Installation instructions are automatically determined by the presence of either

=over 2

=item * A C<Makefile.PL> file in your dist ( Where it assumes C<EUMM> style )

=item * A C<Build.PL> file in your dist ( where it assumes C<Module::Build> style )

=item * In the case of both, only instructions for C<Makefile.PL> will be emitted.

=item * All of the above behavior can be overridden using the L<< C<installer>|/installer >> attribute.

=back

=item * I<ALL> Copyright and license details are extracted from C<main_module> in any C<H1Nest> that has either C<COPYRIGHT> or C<LICENSE> in the heading.

=item * Or failing such a section, a C<COPYRIGHT AND LICENSE> section will be derived from C<< zilla->license >>

=back

=head1 ATTRIBUTES

=head2 installer

Determines what installers to document in the C<INSTALLATION> section.

By default, that section is determined based on the presence of certain
files in your C<dist>.

However, in the event you have multiple installers supported, manually specifying
this attribute allows you to control which, or all, and the order.

  installer = eumm ; # only eumm

  installer = eumm
  installer = mb     ; EUMM shown first, MB shown second

  installer = mb
  installer = eumm   ; EUMM shown second, MB shown first

The verbiage however has not yet been cleaned up such that having both is completely lucid.

=for Pod::Coverage gather_files

=head1 SEE ALSO

Here are some competing modules and how this module differs from them.

=over 4

=item * L<< C<[Readme]>|Dist::Zilla::Plugin::Readme >>

Gives a much briefer more generic C<README> file, which lacks quite as much readable content,
and contains no installation instructions.

=item * L<< C<[ReadmeFromPod]>|Dist::Zilla::Plugin::ReadmeFromPod >>

Provides various output formats, but ultimately is a transformer of your C<main_module>'s C<POD>,
which is excessive for some peoples tastes. ( And lacks install instructions )

=item * L<< C<[ReadmeAnyFromPod]>|Dist::Zilla::Plugin::ReadmeAnyFromPod >>

Based on the above provides a bunch of extra features, but is ultimately limited
in similar ways with regards to install details and verbosity.

=item * L<< C<[Pod2Readme]>|Dist::Zilla::Plugin::Pod2Readme >>

Possibly the most straight forward C<POD> → C<README> translator, but limited like the above
in that it is I<only> a C<POD> translator, but lacks the install instructions aspect.

=item * L<< C<[InstallGuide]>|Dist::Zilla::Plugin::InstallGuide >>

The polar opposite approach that only focuses on elaborate installation instructions in C<INSTALL>,
but lacks any of the C<POD> and C<COPYRIGHT> elements.

=back

=head1 AUTHOR

Kent Fredric <kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Kent Fredric <kentfredric@gmail.com>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
