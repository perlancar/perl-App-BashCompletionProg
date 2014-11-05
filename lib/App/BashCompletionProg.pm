package App::BashCompletionProg;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use File::Slurp::Tiny qw();
use List::Util qw(first);
use Perinci::Object;
use Perinci::Sub::Util qw(err);
use Text::Fragment qw();

our %SPEC;

my $DEBUG = $ENV{DEBUG};
my $re_progname = $Text::Fragment::re_id;

$SPEC{':package'} = {
    v => 1.1,
    summary => "Manage /etc/bash-completion-prog (or ~/.bash-completion-prog)",
};

sub _f_path {
    if ($>) {
        "$ENV{HOME}/.bash-completion-prog";
    } else {
        "/etc/bash-completion-prog";
    }
}

sub _read_parse_f {
    my $path = shift // _f_path();
    my $text = (-f $path) ? File::Slurp::Tiny::read_file($path) : "";
    my $listres = Text::Fragment::list_fragments(text=>$text);
    return $listres if $listres->[0] != 200;
    [200,"OK",{content=>$text, parsed=>$listres->[2]}];
}

sub _write_f {
    my $path = shift // _f_path();
    my $content = shift;
    File::Slurp::Tiny::write_file($path, $content);
    [200];
}

# XXX plugin based
sub _detect_prog {
    my $prog = @_;
}

# add one or more programs
sub _add {
    my $opts; # progs*,

    my %args = @_;

    my $res = _read_parse_f($args{file});
    return err("Can't read entries", $res) if $res->[0] != 200;

    my $content = $res->[2]{content};

    my $envres = envresmulti();
    for my $prog (@{ $opt->{progs} }) {
        say "Adding to bash-completion-f: $prog";
        my $insres = Text::Fragment::insert_fragment(
            text=>$content, id=>$prog->{name},
            payload=>$prog->{command});
        $envres->add_result($insres->[0], $insres->[1],
                            {item_id=>$prog->{prog}});
        next unless $insres->[0] == 200;
        $content = $insres->[2]{text};
    }

    if ($added) {
        my $writeres = _write_f($args{file}, $content);
        return err("Can't write", $writeres) if $writeres->[0] != 200;
    }

    $envres->as_struct;
}

    my $added;
    my @progs;

    if ($opts->{dirs}) {
        for my $dir (@{ $opts->{dirs} }) {
            opendir my($dh), $dir or next;
            say "DEBUG:Searching $dir ..." if $DEBUG;
            for my $prog (readdir $dh) {
                next if $prog eq '.' || $prog eq '..';
                $names{$prog} and next;
                $prog =~ $Text::Fragment::re_id or next;

                my $compprog;
                my $detectres =
                    Perinci::CmdLine::Util::detect_perinci_cmdline_script(
                        script=>"$dir/$prog",
                        include_noexec=>0,
                        include_wrapper=>1);
                $detectres->[0] == 200 or
                    do { warn "Can't detect $prog: $detectres->[1], skipped"; next };
                $detectres->[2] or
                    do { say "DEBUG:Skipping $prog (".$detectres->[3]{'func.reason'}.")" if $DEBUG; next };
                if ($detectres->[3]{'func.is_wrapper'}) {
                    $compprog = $detectres->[3]{'func.wrapped'};
                }
                push @progs, {prog=>$prog, compprog=>$compprog//$prog};
                $added++;
                $names{$prog}++;
            }
        }
    } elsif ($opts->{progs}) {
        for my $prog (@{ $opts->{progs} }) {
            $prog =~ s!.+/!!;
            $names{$prog} and next;
            push @progs, {prog=>$prog, compprog=>$prog};
            $added++;
            $names{$prog}++;
        }
    } else {
        die "BUG: no progs or dirs given";
    }

}

my %arg_file = (file => {
    summary => 'Use alternate location for the bash-completion-f file',
    schema => 'str*',
    description => <<'_',

By default, the `complete` scripts are put in a file either in
`/etc/bash-completion-f` (if running as root) or `~/.bash-completion-f` (if
running as normal user). This option sets another location.

_
    cmdline_aliases => {f=>{}},
});

my %arg_prog = (id => {
    summary => 'Program name',
    schema  => ['str*', {match => $Text::Fragment::re_id}],
    req     => 1,
    pos     => 0,
});

my %arg_prog = (prog => {
    summary => 'Program name(s)',
    schema  => ['array*' => {
        of      => ['str*', {match => $Text::Fragment::re_id}],
        min_len => 1,
    }],
    req     => 1,
    pos     => 0,
    greedy  => 1,
});

my %arg_program = (program => {
    summary => 'Program name(s) to add',
    schema => ['array*' => {
        of => ['str*', {match=>$Text::Fragment::re_id}], # XXX strip dir first before matching
        min_len => 1,
    }],
    req => 1,
    pos => 0,
    greedy => 1,
});

my %arg_dir = (dir => {
    summary => 'Dir and file name(s) to search',
    schema => ['array*' => {
        of => ['str*'], # XXX strip dir first before matching
        min_len => 1,
    }],
    pos => 0,
    greedy => 1,
});

$SPEC{add_entry} = {
    v => 1.1,
    summary => 'Add a completion entry',
    args => {
        %arg_id,
        content => {
            summary => 'Entry content (the actual "complete ..." bash command)',
            schema => 'str*',
            req => 1,
            pos => 1,
        },
        %arg_file,
    },
};
sub add_entry {
    my %args = @_;

    my $id = $args{id};
    my $content = $args{content};

    # XXX schema (coz when we're not using P::C there's no schema validation)
    $id =~ $Text::Fragment::re_id or
        return [400, "Invalid syntax for 'id', please use word only"];

    my $res = _read_parse_f($args{file});
    return err("Can't read entries", $res) if $res->[0] != 200;

    # avoid duplicate
    return [409, "Duplicate id '$id'"]
        if first {$_->{id} eq $id} @{$res->[2]{parsed}};

    # avoid clash with fragment marker
    $content =~ s/^(# (?:BEGIN|END) FRAGMENT)/ $1/gm;

    my $insres = Text::Fragment::insert_fragment(
        text=>$res->[2]{content}, id=>$id, payload=>$content);
    return err("Can't add", $insres) if $insres->[0] != 200;

    my $writeres = _write_f($args{file}, $insres->[2]{text});
    return err("Can't write", $writeres) if $writeres->[0] != 200;

    [200];
}

    _add({entries=>delete($args{program})}, %args);
}

sub _delete_entries {
    my $opts = shift;

    my %args = @_;
    my $res = _read_parse_f($args{file});
    return err("Can't read entries", $res) if $res->[0] != 200;

    my $envres = envresmulti();

    my $content = $res->[2]{content};
    my $deleted;
    for my $entry (@{ $res->[2]{parsed} }) {
        my $parseres = _parse_entry($entry->{payload});
        unless ($parseres->[0] == 200) {
            warn "Can't parse 'complete' command for entry '$entry->{id}': ".
                "$parseres->[1], skipped\n";
            next;
        }
        my $remove;
        if ($opts->{criteria}) {
            $remove = $opts->{criteria}->($parseres->[2]{names});
        } elsif ($opts->{ids}) {
            use experimental 'smartmatch';
            for (@{ $parseres->[2]{names} }) {
                if ($_ ~~ @{ $opts->{ids} }) {
                    $remove++;
                    last;
                }
            }
        } else {
            die "BUG: no criteria nor ids are given";
        }

        next unless $remove;
        say "Removing from bash-completion-f: " . join(", ", @{$parseres->[2]{names}});
        my $delres = Text::Fragment::delete_fragment(
            text=>$content, id=>$entry->{id});
        next if $delres->[0] == 304;
        $envres->add_result($delres->[0], $delres->[1],
                            {item_id=>$entry->{id}});
        next if $delres->[0] != 200;
        $deleted++;
        $content = $delres->[2]{text};
    }

    if ($deleted) {
        my $writeres = _write_f($args{file}, $content);
        return err("Can't write", $writeres) if $writeres->[0] != 200;
    }

    $envres->as_struct;
}

$SPEC{remove_entries} = {
    v => 1.1,
    summary => '',
    args => {
        %arg_ids,
        %arg_file,
    },
};
sub remove_entries {
    my %args = @_;

    _delete_entries(
        {ids=>delete($args{id})},
        %args
    );
}

$SPEC{remove_all_entries} = {
    v => 1.1,
    summary => 'Remove all entries',
    description => <<'_',
_
    args => {
        %arg_file,
    },
};
sub remove_all_entries {
    my %args = @_;
    _delete_entries({criteria=>sub{1}}, %args);
}

$SPEC{list_entries} = {
    v => 1.1,
    summary => '',
    args => {
        %arg_file,
        detail => {
            schema => 'bool',
        },
    },
};
sub list_entries {
    my %args = @_;

    my $res = _read_parse_f($args{file} // _f_path());
    return $res if $res->[0] != 200;

    my @res;
    for (@{ $res->[2]{parsed} }) {
        if ($args{detail}) {
            push @res, {id=>$_->{id}, payload=>$_->{payload}};
        } else {
            push @res, $_->{id};
        }
    }

    [200, "OK", \@res];
}

$SPEC{clean_entries} = {
    v => 1.1,
    summary => 'Delete entries for commands that are not in PATH',
    description => <<'_',

Sometimes when a program gets uninstalled, it still leaves completion entry.
This subcommand will search all entries for commands that are no longer found in
PATH and remove them.

_
    args => {
        %arg_file,
    },
};
sub clean_entries {
    require File::Which;

    my %args = @_;
    _delete_entries(
        {criteria => sub {
             my $names = shift;
             # remove if none of the names in complete command are in PATH
             for my $name (@{ $names }) {
                 if (File::Which::which($name)) {
                     return 0;
                 }
             }
             return 1;
         }},
        %args,
    );
}

$SPEC{add_all_pc} = {
    v => 1.1,
    summary => 'Find all scripts that use Perinci::CmdLine in specified dirs (or PATH)' .
        ' and add completion entries for them',
    description => <<'_',
_
    args => {
        %arg_file,
        %arg_dir,
    },
};
sub add_all_pc {
    my %args = @_;
    _add_pc({dirs => delete($args{dir}) // [split /:/, $ENV{PATH}]}, %args);
}

1;
# ABSTRACT: Backend for bash-completion-f script
