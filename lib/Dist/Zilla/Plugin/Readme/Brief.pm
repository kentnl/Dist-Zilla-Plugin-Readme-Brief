use 5.006;  # our
use strict;
use warnings;

package Dist::Zilla::Plugin::Readme::Brief;

our $VERSION = '0.001000';

# ABSTRACT: Provide a short simple README with just the essentials

our $AUTHORITY = 'cpan:KENTNL'; # AUTHORITY

use Moose qw( with );
with 'Dist::Zilla::Role::PPI';
with 'Dist::Zilla::Role::FileGatherer';

__PACKAGE__->meta->make_immutable;
no Moose;

sub gather_files {
  my ( $self ) = @_;
  require Dist::Zilla::File::FromCode;
  $self->add_file( Dist::Zilla::File::FromCode->new(
    name => "README",
    code => sub {
        return $self->_generate_content;
    },
  ));
}

# Internal Methods

sub _generate_content {
  my ( $self ) = @_;
  return $self->_heading . qq[\n\n] . $self->_description;
}


sub _source_pm_file {
  my ( $self ) = @_;
  return $self->zilla->main_module;
}

sub _source_pod {
  my ( $self ) = @_;
  return $self->{_pod_cache} if exists $self->{_pod_cache};
  my $chars = $self->_source_pm_file->content;

  require Encode;
  require Pod::Elemental;
  require Pod::Elemental::Transformer::Pod5;

  my $octets  = Encode::encode('UTF-8', $chars, Encode::FB_CROAK);
  my $document = Pod::Elemental->read_string( $octets  );
  Pod::Elemental::Transformer::Pod5->new->transform_node($document);
  $self->{_pod_cache} = $document;
  return $document;
}

sub _get_docname_via_statement {
  my ($self, $ppi_document) = @_;
 
  my $pkg_node = $ppi_document->find_first('PPI::Statement::Package');
  return unless $pkg_node;
  return $pkg_node->namespace;
}
 
sub _get_docname_via_comment {
  my ($self, $ppi_document) = @_;
 
  return $self->_extract_comment_content($ppi_document, 'PODNAME');
}

sub _extract_comment_content {
  my ($self, $ppi_document, $key) = @_;
 
  my $regex = qr/^\s*#+\s*$key:\s*(.+)$/m;
 
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
  my ($self, $ppi_document) = @_;
 
  my $docname = $self->_get_docname_via_comment($ppi_document)
             || $self->_get_docname_via_statement($ppi_document);
 
  return $docname;
}

sub _heading {
  my ( $self ) = @_;
  my $document = $self->ppi_document_for_file( $self->_source_pm_file );
  return $self->_get_docname( $document );
}

sub _description {
  my ( $self ) = @_;
  my $pod  = $self->_source_pod;
  my (@nodes) = @{ $pod->children };

  my @found;

  require Pod::Elemental::Selectors;

  for my $node_number ( 0 .. $#nodes ) {
    next unless Pod::Elemental::Selectors::s_command( head1 => $nodes[$node_number] );
    next unless $nodes[$node_number]->content eq 'DESCRIPTION';
    push @found, $nodes[$node_number+1];
  }
  if ( not @found ) {
    $self->log("DESCRIPTION not found in " . $self->_source_pm_file->name );
    return '';
  }
  require Pod::Text;
  my $parser = Pod::Text->new();
  $parser->output_string( \( my $text ) );
  $parser->parse_string_document( $_->as_pod_string ) for @found;
  return $text;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Readme::Brief - Provide a short simple README with just the essentials

=head1 VERSION

version 0.001000

=head1 DESCRIPTION

This provides a terse but informative README file for your CPAN distribution
that contains just the essential details about your dist a casual consumer would want to know.

=over 4

=item * The name of the primary module in the distribution

=item * The distributions main modules description

=item * Simple installation instructions from an extracted archive

=item * Short copyright information

=back

=head1 AUTHOR

Kent Fredric <kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Kent Fredric <kentfredric@gmail.com>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
