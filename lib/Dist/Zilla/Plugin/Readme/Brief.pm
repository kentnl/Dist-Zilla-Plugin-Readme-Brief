use 5.010;    # m regexp propagation
use strict;
use warnings;

package Dist::Zilla::Plugin::Readme::Brief;

our $VERSION = '0.001001';

# ABSTRACT: Provide a short simple README with just the essentials

our $AUTHORITY = 'cpan:KENTNL'; # AUTHORITY

use Moose qw( with );
use List::Util qw( first );
with 'Dist::Zilla::Role::PPI';
with 'Dist::Zilla::Role::FileGatherer';

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
  my $out = q[];
  $out .= $self->_heading . qq[\n\n];
  $out .= $self->_description . qq[\n\n];
  $out .= qq[INSTALLATION\n\n];
  $out .= $self->_install_auto . qq[\n];
  if ( first { $_->name =~ /\AMakefile.PL\z/msx } @{ $self->zilla->files } ) {
    $out .= $self->_install_eumm . qq[\n];
  }
  elsif ( first { $_->name =~ /\ABuild.PL\z/msx } @{ $self->zilla->files } ) {
    $out .= $self->_install_mb . qq[\n];
  }
  if ( my $copy = $self->_copyright_from_pod ) {
    $out .= $copy;
  }
  else {
    $out .= $self->_copyright_from_dist;
  }
  return $out;

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

sub _get_docname_via_statement {
  my ( undef, $ppi_document ) = @_;

  my $pkg_node = $ppi_document->find_first('PPI::Statement::Package');
  return unless $pkg_node;
  return $pkg_node->namespace;
}

sub _get_docname_via_comment {
  my ( $self, $ppi_document ) = @_;

  return $self->_extract_comment_content( $ppi_document, 'PODNAME' );
}

sub _extract_comment_content {
  my ( undef, $ppi_document, $key ) = @_;    ## no critic (Variables::ProhibitUnusedVarsStricter)

  my $regex = qr/^\s*#+\s*$key:\s*(.+)$/mx;  ## no critic (RegularExpressions::RequireDotMatchAnything)

  my $content;
  my $finder = sub {
    my $node = $_[1];
    return 0 unless $node->isa('PPI::Token::Comment');
    if ( $node->content =~ $regex ) {
      $content = $1;
      return 1;
    }
    return 0;
  };

  $ppi_document->find_first($finder);

  return $content;
}

sub _get_docname {
  my ( $self, $ppi_document ) = @_;

  my $docname = $self->_get_docname_via_comment($ppi_document)
    || $self->_get_docname_via_statement($ppi_document);

  return $docname;
}

sub _podtext_nodes {
  my ( undef, @nodes ) = @_;
  require Pod::Text;
  my $parser = Pod::Text->new( loose => 1 );
  $parser->output_string( \( my $text ) );
  $parser->parse_string_document( join qq[\n], '=pod', q[], map { $_->as_pod_string } @nodes );

  # strip extra indent;
  $text =~ s{^[ ]{4}}{}msxg;
  return $text;
}

sub _heading {
  my ($self) = @_;
  my $document = $self->ppi_document_for_file( $self->_source_pm_file );
  return $self->_get_docname($document);
}

sub _description {
  my ($self)  = @_;
  my $pod     = $self->_source_pod;
  my (@nodes) = @{ $pod->children };

  my @found;

  require Pod::Elemental::Selectors;

  for my $node_number ( 0 .. $#nodes ) {
    next unless Pod::Elemental::Selectors::s_command( head1 => $nodes[$node_number] );
    next unless 'DESCRIPTION' eq $nodes[$node_number]->content;
    push @found, $nodes[$node_number];
  }
  if ( not @found ) {
    $self->log( 'DESCRIPTION not found in ' . $self->_source_pm_file->name );
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
    next unless $nodes[$node_number]->content =~ /COPYRIGHT|LICENSE/msx;
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
To install this module automatically, any of the following may work:

  cpanm .
  cpan  .
  cpanp -i .
EOFAUTO
}

sub _install_eumm {
  return <<"EOFEUMM";
To install this module manually

  perl Makefile.PL
  make
  make test
  make install
EOFEUMM
}

sub _install_mb {
  return <<"EOFMB";
To install this module manually

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

version 0.001001

=head1 SYNOPSIS

  [Readme::Brief]
  ; No tunables at this time

=head1 DESCRIPTION

This provides a terse but informative README file for your CPAN distribution
that contains just the essential details about your dist a casual consumer would want to know.

=over 4

=item * The name of the primary module in the distribution

=item * The distributions main modules description

=item * Simple installation instructions from an extracted archive

=item * Short copyright information

=back

=for Pod::Coverage gather_files

=head1 NOTE

This is sill reasonably fresh code and reasonably experimental, and feature enhancements and bug fixes
are actively desired.

However, bugs are highly likely to be encountered, especially as there are no tests.

=head1 MECHANICS

=over 4

=item * Heading is derived from the C<package> statement in C<main_module>

=item * Description is extracted as the entire C<H1Nest> of the section titled C<DESCRIPTION> in C<main_module>

=item * Installation instructions are automatically determined by the presence of either

=over 2

=item * A C<Makefile.PL> file in your dist ( Where it assumes C<EUMM> style )

=item * A C<Build.PL> file in your dist ( where it assumes C<Module::Build> style )

=item * In the case of both, only instructions for C<Makefile.PL> will be emitted. (B<C<TODO>:Be adjustable>)

=back

=item * I<ALL> Copyright and license details are extracted from C<main_module> in any C<H1Nest> that has either C<COPYRIGHT> or C<LICENSE> in the heading.

=item * Or failing such a section, a C<COPYRIGHT AND LICENSE> section will be derived from C<< zilla->license >>

=back

=head1 AUTHOR

Kent Fredric <kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Kent Fredric <kentfredric@gmail.com>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
