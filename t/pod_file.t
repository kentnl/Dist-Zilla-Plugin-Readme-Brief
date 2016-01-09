use strict;
use warnings;

use Test::More;

# ABSTRACT: Basic Test for documentation in .pod

use Dist::Zilla::Util::Test::KENTNL 1.004 qw( dztest );
use Test::DZil qw( simple_ini );

my $test = dztest();
$test->add_file( 'lib/Example.pm'  => 1 );
$test->add_file( 'lib/Example.pod' => <<'EOF' );

# PODNAME: Foo

=head1 DESCRIPTION

This is a description

=cut

1;

EOF

$test->add_file( 'dist.ini' => simple_ini( [ 'GatherDir' => {} ], [ 'Readme::Brief' => {} ], ) );
$test->build_ok;

my $src_file = $test->test_has_built_file('README');
my @lines = $src_file->lines_utf8( { chomp => 1 } );

use List::Util qw( first );

ok( ( first { $_ eq 'Foo' } @lines ),                   'Document name found and injected' );
ok( ( first { $_ eq 'This is a description' } @lines ), 'Description injected' );
ok( ( first { $_ eq 'INSTALLATION' } @lines ),          'Installation section injected' );
ok( ( first { $_ eq 'COPYRIGHT AND LICENSE' } @lines ), 'Copyright section injected' );

done_testing;

