package Perinci::Sub::To::CLIOptSpec;

our $DATE = '2014-11-20'; # DATE
our $VERSION = '0.01'; # VERSION

use 5.010001;
use strict;
use warnings;

use Perinci::Object;

our %SPEC;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(gen_cli_opt_spec_from_meta);

sub _get_cat_from_arg_spec {
    my $arg_spec = shift;
    my $cat;
    for (@{ $arg_spec->{tags} // [] }) {
        if (!ref($_) && /^category:(.+)/) {
            $cat = ucfirst($1) . " options";
            last;
        }
    }
    $cat //= "Options";
}

sub _dash_prefix {
    length($_[0]) > 1 ? "--$_[0]" : "-$_[0]";
}

sub _fmt_opt {
    my $spec = shift;
    my @parsed = @_;
    my @res;
    my $i = 0;
    for my $parsed (@parsed) {
        my $j = 0;
        for (@{ $parsed->{opts} }) {
            my $opt = _dash_prefix($_);
            if ($i==0 && $j==0) {
                if ($parsed->{type}) {
                    if ($spec->{'x.schema.entity'}) {
                        $opt .= "=".$spec->{'x.schema.entity'};
                    } else {
                        $opt .= "=$parsed->{type}";
                    }
                }
                # mark required option with a '*'
                $opt .= "*" if $spec->{req};
            }
            push @res, $opt;
            $j++;
        }
        $i++;
    }
    join ", ", @res;
}

$SPEC{gen_cli_opt_spec_from_meta} = {
    v => 1.1,
    summary => 'From Rinci function metadata, generate structure convenient '.
        'for producing CLI help/usage',
    description => <<'_',

This function calls `Perinci::Sub::GetArgs::Argv`'s
`gen_getopt_long_spec_from_meta()` (or receive it, if passed, to avoid
calculating twice) and post-processes it: produce command usage line, format the
options, include information from metadata, group the options by category. The
resulting data structure is convenient to use when one produces a help message
for a command-line program.

_
    args => {
        meta => {
            schema => 'hash*', # XXX rifunc
            req => 1,
            pos => 0,
        },
        meta_is_normalized => {
            schema => 'bool*',
        },
        common_opts => {
            summary => 'Will be passed to gen_getopt_long_spec_from_meta()',
            schema  => 'hash*',
        },
        ggls_res => {
            summary => 'Full result from gen_getopt_long_spec_from_meta()',
            schema  => 'array*', # XXX envres
            description => <<'_',

If you already call `Perinci::Sub::GetArgs::Argv`'s
`gen_getopt_long_spec_from_meta()`, you can pass the _full_ enveloped result
here, to avoid calculating twice. What will be useful for the function is the
extra result in result metadata (`func.*` keys in `$res->[3]` hash).

_
        },
        lang => {
            schema => 'str*',
        },
    },
    result => {
        schema => 'hash*',
    },
};
sub gen_cli_opt_spec_from_meta {
    my %args = @_;

    my $lang = $args{lang};
    my $meta = $args{meta} or return [400, 'Please specify meta'];
    my $common_opts = $args{common_opts};
    unless ($args{meta_is_normalized}) {
        require Perinci::Sub::Normalize;
        $meta = Perinci::Sub::Normalize::normalize_function_metadata($meta);
    }
    my $ggls_res = $args{ggls_res} // do {
        require Perinci::Sub::GetArgs::Argv;
        Perinci::Sub::GetArgs::Argv::gen_getopt_long_spec_from_meta(
            meta=>$meta, meta_is_normalized=>1, common_opts=>$common_opts,
        );
    };
    $ggls_res->[0] == 200 or return $ggls_res;

    my $args_prop = $meta->{args} // {};
    my $cliospec = {};

    # generate usage line
    {
        my @args;
        my %args_prop = %$args_prop; # copy because we want to iterate & delete
        my $max_pos = -1;
        for (values %args_prop) {
            $max_pos = $_->{pos}
                if defined($_->{pos}) && $_->{pos} > $max_pos;
        }
        my $pos = 0;
        while ($pos <= $max_pos) {
            my ($arg, $arg_spec);
            for (keys %args_prop) {
                $arg_spec = $args_prop{$_};
                if (defined($arg_spec->{pos}) && $arg_spec->{pos}==$pos) {
                    $arg = $_;
                    last;
                }
            }
            next unless defined($arg);
            if ($arg_spec->{req}) {
                push @args, "<$arg>";
            } else {
                push @args, "[$arg]";
            }
            push @args, "..." if $arg_spec->{greedy};
            delete $args_prop{$arg};
            $pos++;
        }
        unshift @args, "[options]" if keys %args_prop; # XXX translatable?
        $cliospec->{usage_line} = "[[prog]]".
            (@args ? " ".join(" ", @args) : "");
    }

    # group options by category, combine options with its alias(es) that can be
    # combined
    my %opts;
    {
        my $ospecs = $ggls_res->[3]{'func.specmeta'};
        # separate groupable aliases because they will be merged with the
        # argument options
        my (@k, @k_aliases);
      OSPEC1:
        for (sort keys %$ospecs) {
            my $ospec = $ospecs->{$_};
            {
                last unless $ospec->{is_alias};
                next if $ospec->{is_code};
                my $arg_spec = $args_prop->{$ospec->{arg}};
                my $alias_spec = $arg_spec->{cmdline_aliases}{$ospec->{alias}};
                next if $alias_spec->{summary};
                push @k_aliases, $_;
                next OSPEC1;
            }
            push @k, $_;
        }

        my %negs; # key=arg, only show one negation form for each arg option

      OSPEC2:
        while (@k) {
            my $k = shift @k;
            my $ospec = $ospecs->{$k};
            my $ok;

            if ($ospec->{is_alias}) {
                # non-groupable alias

                my $arg_spec = $args_prop->{ $ospec->{arg} };
                my $alias_spec = $arg_spec->{cmdline_aliases}{$ospec->{alias}};
                my $rimeta = rimeta($alias_spec);
                $ok = _fmt_opt($arg_spec, $ospec->{parsed});
                $opts{$ok} = {
                    is_alias => 1,
                    alias_for => $ospec->{alias_for},
                    category => _get_cat_from_arg_spec($arg_spec),
                    summary => $rimeta->langprop({lang=>$lang}, 'summary') //
                        "Alias for "._dash_prefix($ospec->{parsed}{opts}[0]),
                    description =>
                        $rimeta->langprop({lang=>$lang}, 'description'),
                };
            } elsif (defined $ospec->{arg}) {
                # an option for argument

                my $arg_spec = $args_prop->{$ospec->{arg}};
                my $rimeta = rimeta($arg_spec);
                my $opt = {
                    category => _get_cat_from_arg_spec($arg_spec),
                };

                # for bool, only display either the positive (e.g. --bool) or
                # the negative (e.g. --nobool) depending on the default
                if (defined($ospec->{is_neg})) {
                    my $default = $arg_spec->{default} //
                        $arg_spec->{schema}[1]{default};
                    next OSPEC2 if  $default && !$ospec->{is_neg};
                    next OSPEC2 if !$default &&  $ospec->{is_neg};
                    if ($ospec->{is_neg}) {
                        next OSPEC2 if $negs{$ospec->{arg}}++;
                    }
                }

                if ($ospec->{is_neg}) {
                    # for negative option, use summary.alt.neg instead of
                    # summary
                    $opt->{summary} =
                        $rimeta->langprop({lang=>$lang}, 'summary.alt.neg');
                } else {
                    $opt->{summary} =
                        $rimeta->langprop({lang=>$lang}, 'summary');
                }
                $opt->{description} =
                    $rimeta->langprop({lang=>$lang}, 'description');

                # find aliases that can be grouped together with this option
                my @aliases;
                my $j = $#k_aliases;
                while ($j >= 0) {
                    my $aospec = $ospecs->{ $k_aliases[$j] };
                    {
                        last unless $aospec->{arg} eq $ospec->{arg};
                        push @aliases, $aospec->{parsed};
                        splice @k_aliases, $j, 1;
                    }
                    $j--;
                }

                $ok = _fmt_opt($arg_spec, $ospec->{parsed}, @aliases);

                for (qw/req pos greedy is_password/) {
                    $opt->{$_} = $arg_spec->{$_} if defined $arg_spec->{$_};
                }
                $opts{$ok} = $opt;
            } else {
                # option from common_opts
                $ok = _fmt_opt($common_opts, $ospec->{parsed});
                my $rimeta = rimeta($common_opts->{$ospec->{common_opt}});
                $opts{$ok} = {
                    category => "Common options", # XXX translatable?
                    summary => $rimeta->langprop({lang=>$lang}, 'summary'),
                    description =>
                        $rimeta->langprop({lang=>$lang}, 'description'),
                };
            }
        }
    }
    $cliospec->{opts} = \%opts;

    [200, "OK", $cliospec];
}

1;
# ABSTRACT: Generate data structure convenient for producing CLI help/usage

__END__

=pod

=encoding UTF-8

=head1 NAME

Perinci::Sub::To::CLIOptSpec - Generate data structure convenient for producing CLI help/usage

=head1 VERSION

This document describes version 0.01 of Perinci::Sub::To::CLIOptSpec (from Perl distribution Perinci-Sub-To-CLIOptSpec), released on 2014-11-20.

=head1 SYNOPSIS

 use Perinci::Sub::To::CLIOptSpec qw(gen_cli_opt_spec_from_meta);
 my $cliospec = gen_cli_opt_spec_from_meta(meta => $meta);

=head1 FUNCTIONS


=head2 gen_cli_opt_spec_from_meta(%args) -> [status, msg, result, meta]

From Rinci function metadata, generate structure convenient for producing CLI help/usage.

This function calls C<Perinci::Sub::GetArgs::Argv>'s
C<gen_getopt_long_spec_from_meta()> (or receive it, if passed, to avoid
calculating twice) and post-processes it: produce command usage line, format the
options, include information from metadata, group the options by category. The
resulting data structure is convenient to use when one produces a help message
for a command-line program.

Arguments ('*' denotes required arguments):

=over 4

=item * B<common_opts> => I<hash>

Will be passed to gen_getopt_long_spec_from_meta().

=item * B<ggls_res> => I<array>

Full result from gen_getopt_long_spec_from_meta().

If you already call C<Perinci::Sub::GetArgs::Argv>'s
C<gen_getopt_long_spec_from_meta()>, you can pass the I<full> enveloped result
here, to avoid calculating twice. What will be useful for the function is the
extra result in result metadata (C<func.*> keys in C<< $res-E<gt>[3] >> hash).

=item * B<lang> => I<str>

=item * B<meta>* => I<hash>

=item * B<meta_is_normalized> => I<bool>

=back

Return value:

Returns an enveloped result (an array).

First element (status) is an integer containing HTTP status code
(200 means OK, 4xx caller error, 5xx function error). Second element
(msg) is a string containing error message, or 'OK' if status is
200. Third element (result) is optional, the actual result. Fourth
element (meta) is called result metadata and is optional, a hash
that contains extra information.

 (hash)

=head1 SEE ALSO

L<Perinci::CmdLine>, L<Perinci::CmdLine::Lite>

L<Pod::Weaver::Plugin::Rinci>

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/Perinci-Sub-To-CLIOptSpec>.

=head1 SOURCE

Source repository is at L<https://github.com/perlancar/perl-Perinci-Sub-To-CLIOptSpec>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=Perinci-Sub-To-CLIOptSpec>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

perlancar <perlancar@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by perlancar@cpan.org.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
