package CPAN::Critic::Module::Abstract;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
use SHARYANTO::Package::Util qw(list_package_contents);
use Perinci::Sub::DepChecker qw(check_deps);
use Perinci::Sub::dep::pm;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       critic_cpan_module_abstract
                       declare_policy
               );

# VERSION

our %PROFILES;
our %SPEC;

sub declare_policy {
    my %args = @_;
    my $name = $args{name} or die "Please specify name";
    $SPEC{"policy_$name"} and die "Policy $name already declared";
    #$args{summary} or die "Please specify summary";

    my $meta = {
        v => 1.1,
        summary => $args{summary},
    };
    $meta->{deps} = $args{deps} if $args{deps};
    $meta->{args} = {
        abstract => {req=>1, schema=>'str*'},
        stash    => {schema=>'hash*'},
    };
    if ($args{args}) {
        for (keys %{ $args{args} }) {
            $meta->{args}{$_} = $args{args}{$_};
        }
    }
    $meta->{"_cpancritic.severity"} = $args{severity} // 3;
    $meta->{"_cpancritic.themes"}   = $args{themes} // [];

    no strict 'refs';
    *{__PACKAGE__."::policy_$name"} = $args{code};
    $SPEC{"policy_$name"} = $meta;
}

declare_policy
    name => 'prohibit_empty',
    severity => 5,
    code => sub {
        my %args = @_;
        my $ab = $args{abstract};
        if ($ab =~ /\S/) {
            [200];
        } else {
            [409];
        }
    };

declare_policy
    name => 'prohibit_too_short',
    severity => 4,
    args => {
        min_len => {schema=>['int*', default=>3]},
    },
    code => sub {
        my %args = @_;
        my $ab = $args{abstract};
        my $l  = $args{min_len} // 3;
        if (!length($ab)) {
            [412];
        } elsif (length($ab) >= $l) {
            [200];
        } else {
            [409];
        }
    };

declare_policy
    name => 'prohibit_too_long',
    severity => 3,
    args => {
        max_len => {schema=>['int*', default=>72]},
    },
    code => sub {
        my %args = @_;
        my $ab = $args{abstract};
        my $l  = $args{max_len} // 72;
        if (length($ab) <= $l) {
            [200];
        } else {
            [409];
        }
    };

declare_policy
    name => 'prohibit_multiline',
    severity => 3,
    args => {},
    code => sub {
        my %args = @_;
        my $ab = $args{abstract};
        if ($ab !~ /\n/) {
            [200];
        } else {
            [409];
        }
    };

declare_policy
    name => 'prohibit_template',
    severity => 5,
    args => {},
    code => sub {
        my %args = @_;
        my $ab = $args{abstract};
        if ($ab =~ /^(Perl extension for blah blah blah)/i) {
            [409, "Template from h2xs '$1'"];
        } elsif ($ab =~ /^(The great new )\w+(::\w+)*/i) {
            [409, "Template from module-starter '$1'"];
        } else {
            [200];
        }
    };

declare_policy
    name => 'prohibit_starts_with_lowercase_letter',
    severity => 2,
    args => {},
    code => sub {
        my %args = @_;
        my $ab = $args{abstract};
        if (!length($ab)) {
            [412];
        } elsif ($ab =~ /^[[:lower:]]/) {
            [409];
        } else {
            [200];
        }
    };

declare_policy
    name => 'prohibit_ends_with_full_stop',
    severity => 2,
    args => {},
    code => sub {
        my %args = @_;
        my $ab = $args{abstract};
        if ($ab =~ /\.\z/) {
            [409];
        } else {
            [200];
        }
    };

declare_policy
    name => 'prohibit_redundancy',
    severity => 3,
    args => {},
    code => sub {
        my %args = @_;
        my $ab = $args{abstract};
        if ($ab =~ /^( (?: (?:a|the) \s+)?
                        (?: perl\s?[56]? \s+)? (?:extension|module|library)
                        (?: \s+ (?:to|for))?
                    )/xi) {
            [409, "Saying '$1' is redundant, omit it"];
        } else {
            [200];
        }
    };

declare_policy
    name => 'require_english',
    severity => 2,
    args => {},
    deps => {pm=>'Lingua::Identify'},
    code => sub {
        my %args = @_;
        my $ab = $args{abstract};
        my %langs = Lingua::Identify::langof($ab);
        return [412, "Empty result from langof"] unless keys(%langs);
        my @langs = sort { $langs{$b}<=>$langs{$a} } keys %langs;
        my $confidence = Lingua::Identify::confidence(%langs);
        $log->tracef(
            "Lingua::Identify result: langof=%s, langs=%s, confidence=%s",
            \%langs, \@langs, $confidence);
        if ($langs[0] ne 'en') {
            [409, "Language not detected as English, ".
                 sprintf("%d%% %s (confidence %.2f)",
                         $langs{$langs[0]}*100, $langs[0], $confidence)];
        } else {
            [200];
        }
    };

declare_policy
    name => 'prohibit_shouting',
    severity => 2,
    args => {},
    code => sub {
        my %args = @_;
        my $ab = $args{abstract};
        if ($ab =~ /!{3,}/) {
            [409, "Too many exclamation points"];
        } else {
            my $spaces = 0; $spaces++ while $ab =~ s/\s+//;
            $ab =~ s/\W+//g;
            $ab =~ s/\d+//g;
            if ($ab =~ /^[[:upper:]]+$/ && $spaces >= 2) {
                return [409, "All-caps"];
            } else {
                return [200];
            }
        }
    };

# policy: don't repeat module name
# policy: should be verb + ...

$PROFILES{all} = {
    policies => [],
};
for (keys %{ { list_package_contents(__PACKAGE__) } }) {
    next unless /^policy_(.+)/;
    push @{$PROFILES{all}{policies}}, $1;
}
$PROFILES{default} = $PROFILES{all};
# XXX default: 4/5 if length > 100?

$SPEC{critic_cpan_module_abstract} = {
    v => 1.1,
    args => {
        abstract => {
            schema => 'str*',
            req => 1,
            pos => 0,
        },
        profile => {
            schema => ['str*' => {default=>'default'}],
        },
    },
};
sub critic_cpan_module_abstract {
    my %args = @_;
    my $abstract = $args{abstract} // "";
    my $profile  = $args{profile} // "default";

    # some cleanup for abstract
    for ($abstract) {
        s/\A\s+//; s/\s+\z//;
    }

    my $pr = $PROFILES{$profile} or return [400, "No such profile '$profile'"];

    my @res;
    $log->tracef("Running critic profile %s on abstract %s ...",
                 $profile, $abstract);
    my $pass;
    my $stash = {};
    for my $pol0 (@{ $pr->{policies} }) {
        $log->tracef("Running policy %s ...", $pol0);
        my $pol = ref($pol0) eq 'HASH' ? %$pol0 : {name=>$pol0};
        my $spec = $SPEC{"policy_$pol->{name}"} or
            return [400, "No such policy $pol->{name}"];
        if ($spec->{deps}) {
            my $err = check_deps($spec->{deps});
            return [500, "Can't run policy $pol->{name}: ".
                        "dependency failed: $err"] if $err;
        }
        no strict 'refs';
        my $code = \&{__PACKAGE__ . "::policy_$pol->{name}"};
        my $res = $code->(abstract=>$abstract, stash=>$stash); # XXX args
        $log->tracef("Result from policy %s: %s", $pol->{name}, $res);
        if ($res->[0] == 409) {
            my $severity = $spec->{"_cpancritic.severity"};
            $pass = 0 if $severity >= 5;
            push @res, {
                severity=>$severity,
                message=>$res->[1] // "Violates $pol->{name}",
            };
        }
    }
    $pass //= 1;

    #[200, "OK", {pass=>$pass, detail=>\@res}];
    [200, "OK", \@res];
}

1;
# ABSTRACT: Critic CPAN module abstract

=head1 SYNOPSIS

 % critic-cpan-module-abstract 'Perl extension for blah blah blah'

 # customize profile (add/remove policies, modify severities, ...)
 # TODO


=head1 DESCRIPTION

This is a proof-of-concept module to critic CPAN module abstract.

Dist::Zilla plugin coming shortly.

=cut
