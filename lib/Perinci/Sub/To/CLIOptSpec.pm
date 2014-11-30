package Perinci::Sub::To::CLIOptSpec;

our $DATE = '2014-11-30'; # DATE
our $VERSION = '0.08'; # VERSION

use 5.010001;
use strict;
use warnings;

use Perinci::Object;

our %SPEC;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(gen_cli_opt_spec_from_meta);

sub _add_category_from_arg_spec {
    my ($opt, $arg_spec) = @_;
    my $cat;
    my $raw_cat = '';
    for (@{ $arg_spec->{tags} // [] }) {
        my $tag_name = ref($_) ? $_->{name} : $_;
        if ($tag_name =~ /^category:(.+)/) {
            $raw_cat = $1;
            $cat = ucfirst($1) . " options";
            last;
        }
    }
    $cat //= "Options";
    $opt->{category} = $cat;
    $opt->{raw_category} = $raw_cat;
}

sub _add_default_from_arg_spec {
    my ($opt, $arg_spec) = @_;
    if (exists $arg_spec->{default}) {
        $opt->{default} = $arg_spec->{default};
    } elsif ($arg_spec->{schema} && exists($arg_spec->{schema}[1]{default})) {
        $opt->{default} = $arg_spec->{schema}[1]{default};
    }
}

sub _dash_prefix {
    length($_[0]) > 1 ? "--$_[0]" : "-$_[0]";
}

sub _fmt_opt {
    my $spec = shift;
    my @ospecs = @_;
    my @res;
    my $i = 0;
    for my $ospec (@ospecs) {
        my $j = 0;
        my $parsed = $ospec->{parsed};
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
                $opt .= "*" if $spec->{req} && !$ospec->{is_base64} &&
                    !$ospec->{is_json} && !$ospec->{is_yaml};
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
`gen_getopt_long_spec_from_meta()` (or receive its result as an argument, if
passed, to avoid calling the function twice) and post-processes it: produce
command usage line, format the options, include information from metadata, group
the options by category. The resulting data structure is convenient to use when
one produces a help message for a command-line program.

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
        per_arg_json => {
            schema => 'bool',
            summary => 'Pass per_arg_json=1 to Perinci::Sub::GetArgs::Argv',
        },
        per_arg_yaml => {
            schema => 'bool',
            summary => 'Pass per_arg_json=1 to Perinci::Sub::GetArgs::Argv',
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
            per_arg_json => $args{per_arg_json},
            per_arg_yaml => $args{per_arg_yaml},
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
        unshift @args, "[options]" if keys(%args_prop) || keys(%$common_opts); # XXX translatable?
        $cliospec->{usage_line} = "[[prog]]".
            (@args ? " ".join(" ", @args) : "");
    }

    # generate list of options: group options by category, combine options with
    # its alias(es) that can be combined
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

            if ($ospec->{is_alias} || defined($ospec->{arg})) {
                my $arg_spec;
                my $opt;

                if ($ospec->{is_alias}) {
                    # non-groupable alias

                    $arg_spec = $args_prop->{ $ospec->{arg} };
                    my $alias_spec = $arg_spec->{cmdline_aliases}{$ospec->{alias}};
                    my $rimeta = rimeta($alias_spec);
                    $ok = _fmt_opt($arg_spec, $ospec);
                    $opt = {
                        orig_opt => $k,
                        is_alias => 1,
                        alias_for => $ospec->{alias_for},
                        summary => $rimeta->langprop({lang=>$lang}, 'summary') //
                            "Alias for "._dash_prefix($ospec->{parsed}{opts}[0]),
                        description =>
                        $rimeta->langprop({lang=>$lang}, 'description'),
                    };
                } else {
                    # an option for argument

                    $arg_spec = $args_prop->{$ospec->{arg}};
                    my $rimeta = rimeta($arg_spec);
                    $opt = {
                        orig_opt => $k,
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
                            push @aliases, $aospec;
                            splice @k_aliases, $j, 1;
                        }
                        $j--;
                    }

                    $ok = _fmt_opt($arg_spec, $ospec, @aliases);
                }

                $opt->{arg_spec} = $arg_spec;

                # include keys from func.specmeta
                for (qw/arg fqarg is_base64 is_json is_yaml/) {
                    $opt->{$_} = $ospec->{$_} if defined $ospec->{$_};
                }

                # include keys from arg_spec
                for (qw/req pos greedy is_password links tags/) {
                    $opt->{$_} = $arg_spec->{$_} if defined $arg_spec->{$_};
                }

                _add_category_from_arg_spec($opt, $arg_spec);
                _add_default_from_arg_spec($opt, $arg_spec);

                $opts{$ok} = $opt;

            } else {
                # option from common_opts

                $ok = _fmt_opt($common_opts, $ospec);
                my $rimeta = rimeta($common_opts->{$ospec->{common_opt}});
                $opts{$ok} = {
                    orig_opt => $k,
                    category => "Common options", # XXX translatable?
                    summary => $rimeta->langprop({lang=>$lang}, 'summary'),
                    description =>
                        $rimeta->langprop({lang=>$lang}, 'description'),
                };

            }
        }

        # link ungrouped alias to its main opt
      OPT1:
        for my $k (keys %opts) {
            my $opt = $opts{$k};
            next unless $opt->{is_alias} || $opt->{is_base64} ||
                $opt->{is_json} || $opt->{is_yaml};
            for my $k2 (keys %opts) {
                my $arg_opt = $opts{$k2};
                next if $arg_opt->{is_alias} || $arg_opt->{is_base64} ||
                    $arg_opt->{is_json} || $arg_opt->{is_yaml};
                next unless defined($arg_opt->{arg}) &&
                    $arg_opt->{arg} eq $opt->{arg};
                $opt->{main_opt} = $k2;
                next OPT1;
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

This document describes version 0.08 of Perinci::Sub::To::CLIOptSpec (from Perl distribution Perinci-Sub-To-CLIOptSpec), released on 2014-11-30.

=head1 SYNOPSIS

 use Perinci::Sub::To::CLIOptSpec qw(gen_cli_opt_spec_from_meta);
 my $cliospec = gen_cli_opt_spec_from_meta(meta => $meta);

=head1 FUNCTIONS


=head2 gen_cli_opt_spec_from_meta(%args) -> [status, msg, result, meta]

From Rinci function metadata, generate structure convenient for producing CLI help/usage.

This function calls C<Perinci::Sub::GetArgs::Argv>'s
C<gen_getopt_long_spec_from_meta()> (or receive its result as an argument, if
passed, to avoid calling the function twice) and post-processes it: produce
command usage line, format the options, include information from metadata, group
the options by category. The resulting data structure is convenient to use when
one produces a help message for a command-line program.

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

=item * B<per_arg_json> => I<bool>

Pass per_arg_json=1 to Perinci::Sub::GetArgs::Argv.

=item * B<per_arg_yaml> => I<bool>

Pass per_arg_json=1 to Perinci::Sub::GetArgs::Argv.

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
