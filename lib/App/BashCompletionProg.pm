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
    [200,"OK",{path=>$path, content=>$text, parsed=>$listres->[2]}];
}

sub _write_f {
    my $path = shift // _f_path();
    my $content = shift;
    File::Slurp::Tiny::write_file($path, $content);
    [200];
}

# XXX plugin based
sub _detect_prog {
}

# add one or more programs
sub _add {
    my %args = @_;

    my $readres = _read_parse_f($args{file});
    return err("Can't read entries", $readres) if $readres->[0] != 200;

    my %existing_progs = map {$_->{id}=>1} @{ $readres->[2]{parsed} };

    my $content = $readres->[2]{content};

    my $envres = envresmulti();
  PROG:
    for my $prog0 (@{ $args{_progs} }) {
        my $prog = $prog0; $prog =~ s!.+/!!:
        if ($args{ignore}) {
            if ($existing_progs{ $prog }) {
                say "Entry already exists in $readres->[2]{path}: ".
                    "$prog, skipped";
                next PROG;
            } else {
                say "Adding entry to $readres->[2]{path}: $prog->{name}";
            }
        } else {
            if ($existing_progs{ $prog->{name} }) {
                warn "Entry already exists in $readres->[2]{path}: ".
                    "$prog->{name}, replacing\n" unless $args{replace};
            } else {
                say "Adding entry to $readres->[2]{path}: $prog->{name}";
            }
        }

        my $insres = Text::Fragment::insert_fragment(
            text=>$content, id=>$prog->{name},
            payload=>$prog->{command});
        $envres->add_result($insres->[0], $insres->[1],
                            {item_id=>$prog->{name}});
        next unless $insres->[0] == 200;
        $content = $insres->[2]{text};
    }

    if ($added) {
        my $writeres = _write_f($args{file}, $content);
        return err("Can't write", $writeres) if $writeres->[0] != 200;
    }

    $envres->as_struct;
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

sub _delete {
    my %args = @_;
    my $readres = _read_parse_f($args{file});
    return err("Can't read entries", $res) if $readres->[0] != 200;

    my $envres = envresmulti();

    my $content = $readres->[2]{content};
    my $deleted;
    for my $entry (@{ $readres->[2]{parsed} }) {
        my $remove;
        if ($args{criteria}) {
            $remove = $args{criteria}->($entry);
        } elsif ($args{progs}) {
            use experimental 'smartmatch';
            $remove = 1 if $entry->{id} ~~ @{ $args{progs} };
        } else {
            die "BUG: no criteria nor progs are given";
        }

        next unless $remove;
        say "Removing from bash-completion-prog: $entry->{id}";
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

sub _list {
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
