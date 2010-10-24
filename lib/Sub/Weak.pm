use strict;
use warnings;

# ABSTRACT: Create a subroutine with declared weak lexicals

package Sub::Weak;

use Carp                                qw( croak );
use Text::Trim              1.02        qw( trim );
use Devel::Declare          0.006000;
use Data::Dump                          qw( pp );
use B::Hooks::EndOfScope    0.09;
use Sub::Install            0.925       qw( install_sub );
use Scalar::Util                        qw( weaken );

use syntax qw( function method );
use namespace::clean;

sub import {
    my ($class, %args) = @_;

    $args{-as}      ||= 'weaksub';
    $args{-into}    ||= scalar caller;

    Devel::Declare->setup_for(
        $args{-into} => {
            $args{-as} => {
                const => sub {
                    require Devel::Declare::Context::Simple;
                    my $ctx = Devel::Declare::Context::Simple->new;
                    $ctx->init(@_);
                    return $class->_modify($ctx);
                },
            },
        },
    );

    install_sub {
        into    => $args{-into},
        code    => $class->_make_callback,
        as      => $args{-as},
    };

    on_scope_end {
        namespace::clean->clean_subroutines($args{-into}, $args{-as});
    };

    return 1;
}

method _make_callback ($class:) {

    return fun ($code, @weak) {
        return $code->(@weak);
    };
}

method _parse_vars ($class: $vars) {

    $vars =~ s{
        (?:
            \A
            [,\s]*
          |
            [,\s]*
            \Z
        )
    }{}gx;

    return [ map {
        my $var = trim $_;
        $var =~ m{ \A (?: \$ | \% | \@ ) [a-z_][a-z0-9_]* \Z }xi
            or croak "Invalid parameter specification '$var'";
        $var;
    } split qr{\s*(?:,\s*)+}, $vars ];
}

method _parse_proto ($class: $proto) {

    my ($weak_proto, $args_proto) = split qr{;}, $proto;
    my ($weak_vars, $args_vars)   = map {
        $class->_parse_vars(defined($_) ? $_ : '');
    } $weak_proto, $args_proto;
}

method _modify ($class: $ctx) {

    $ctx->skip_declarator;
    $ctx->skipspace;

    my $proto = $ctx->strip_proto
        or croak sprintf q{Expected signature after %s keyword},
          $ctx->declarator;

    my ($weak, $args) = $class->_parse_proto($proto);
    $ctx->skipspace;

    $ctx->inject_if_block(
        $class->_render_block_code($args, $weak),
        $class->_render_weakening_code($weak),
    ) or croak sprintf q{Expected block after %s signature},
        $ctx->declarator;
}

method _inject_block_end ($class: $values) {

    on_scope_end {
        my $linestr = Devel::Declare::get_linestr;
        my $offset  = Devel::Declare::get_linestr_offset;
        substr($linestr, $offset, 0) = sprintf q!; }, %s)!,
            join ', ', @$values;
        Devel::Declare::set_linestr($linestr);
    };
}

method _render_block_code ($class: $args, $weak) {

    return sprintf q{%s %s},
        sprintf('BEGIN { %s->%s(%s) };',
            $class,
            '_inject_block_end',
            pp($weak),
        ),
        @$args ? sprintf(
            'my (%s) = @_;',
            join ', ', @$args,
        ) : '';
}

method _render_weakening_code ($class: $weak) {

    return sprintf q!(sub { my (%s) = @_; ref and %s($_) for (%s); return sub !,
        join(', ', @$weak),
        'Scalar::Util::weaken',
        join(', ', @$weak);
}

1;

__END__

=head1 SYNOPSIS

    use Sub::Weak;

    my $outer_ref = [1 .. 23];

    my $weak_join = weaksub ($outer_ref; $sep) {

        # this $outer_ref is weak
        return join $sep, @$outer_ref;
    };

    say $weak_join->(',');

=head1 DESCRIPTION

This module exports a syntax handler named C<weaksub>. The keyword allows you
to declaratively create code references that hold weak references to outer
lexicals. The simplest form is

    weaksub ($ref) { ... }

The C<$ref> is assumed to be available in the outer scope. The body of the
C<weaksub> expression will have a weakened lexical named C<$ref> available for
access.

If you want to declare additional parameters, you can separate them with a
semicolon (C<;>):

    weaksub ($ref; $arg) { ... }

The C<$arg> value will hold the first argument passed in to the code reference.

You are of course not limited to simple scalar variables. The following works
as well:

    weaksub ($ref, %ref_map; $arg, @rest_args) { ... }

C<Sub::Weak> will take care to only weaken reference arguments, so things like
strings as hash keys are skipped.

=head1 SEE ALSO

L<Devel::Declare>,
L<Function::Parameters>

=cut
