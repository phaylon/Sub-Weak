use strict;
use warnings;

use Test::Most      0.22;
use Devel::Refcount 0.07    qw( refcount );
use Scalar::Util            qw( isweak );
use Sub::Weak;

my $ref  = [1..5];
my $deep = [3, $ref, 5];

sub default {
    return sub {
        ok !isweak($ref), 'not weak by default';
    };
}

sub weakened {
    return weaksub ($ref) {
        ok isweak($ref), 'weak in weaksub';
    };
}

default->();
weakened->();

my $w1 = [1..5];
my %w2 = (foo => [4..7], bar => [9..23]);

my $complex = weaksub ($w1, %w2; $a1, @a2) {
    ok isweak($w1), 'scalar is weak';
    ok isweak($w2{ $_ }), "$_ value is weak"
        for keys %w2;
    ok !isweak($a1), 'argument is not weak';
    ok !isweak($a2[ $_ ]), "item $_ is not weak"
        for 0 .. $#a2;
};

$complex->([1..5], [7..10], [34..55]);

done_testing;
