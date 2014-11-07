package App::BashCompletionProg;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use File::Slurp::Tiny qw();
use File::Which;
use List::Util qw(first);
use Perinci::Object;
use Perinci::Sub::Util qw(err);
use String::ShellQuote;
use Text::Fragment qw();

my $ME = "bash-completion-prog";

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
sub _detect_file {
    my ($prog, $path) = @_;
    say "D:detecting $prog ($path)";
    open my($fh), "<", $path or return [500, "Can't open: $!"];
    read $fh, my($buf), 2;
    my $is_script = $buf eq '#!';

    # currently we don't support non-scripts at all
    return [200, "OK", 0] if !$is_script;

    my $is_perl_script = <$fh> =~ /perl/;
    seek $fh, 0, 0;
    my $content = do { local $/; ~~<$fh> };

    if ($content =~
            /^\s*# FRAGMENT id=bash-completion-prog-hints command=(.+)$/m) {
        return [200, "OK", 1, {
            "func.command"=>"complete -C ".shell_quote($1)." $prog"}];
    } elsif ($is_perl_script && $content =~
                 /^\s*(use|require)\s+Perinci::CmdLine(::Any|::Lite)?/m) {
        return [200, "OK", 1, {
            "func.command"=>"complete -C $prog $prog"}];
    }
    [200, "OK", 0];
}

# add one or more programs
sub _add {
    my %args = @_;

    use DD; dd \%args;

    my $readres = _read_parse_f($args{file});
    return err("Can't read entries", $readres) if $readres->[0] != 200;

    my %existing_progs = map {$_->{id}=>1} @{ $readres->[2]{parsed} };

    my $content = $readres->[2]{content};

    my $added;
    my $envres = envresmulti();
  PROG:
    for my $prog0 (@{ $args{progs} }) {
        my $path;
        say "D:prog0=$prog0\n";
        if ($prog0 =~ m!/!) {
            $path = $prog0;
            unless (-f $path) {
                warn "$ME: No such file '$path', skipped\n";
                $envres->add_result(404, "No such file", {item_id=>$prog0});
                next PROG;
            }
        } else {
            $path = which($prog0);
            unless ($path) {
                warn "$ME: '$prog0' not found in PATH, skipped\n";
                $envres->add_result(404, "Not in PATH", {item_id=>$prog0});
                next PROG;
            }
        }
        my $prog = $prog0; $prog =~ s!.+/!!;
        my $detectres = _detect_file($prog, $path);
        if ($detectres->[0] != 200) {
            warn "$ME: Can't detect '$prog': $detectres->[1]\n";
            $envres->add_result($detectres->[0], $detectres->[1],
                                {item_id=>$prog0});
            next PROG;
        }
        if (!$detectres->[2]) {
            # we simply ignore undetected programs
            next PROG;
        }

        if ($args{ignore}) {
            if ($existing_progs{$prog}) {
                say "Entry already exists in $readres->[2]{path}: ".
                    "$prog, skipped";
                next PROG;
            } else {
                say "Adding entry to $readres->[2]{path}: $prog";
            }
        } else {
            if ($existing_progs{$prog}) {
                warn "Entry already exists in $readres->[2]{path}: ".
                    "$prog, replacing\n" unless $args{replace};
            } else {
                say "Adding entry to $readres->[2]{path}: $prog";
            }
        }

        my $insres = Text::Fragment::insert_fragment(
            text=>$content, id=>$prog,
            payload=>$detectres->[3]{'func.command'});
        $envres->add_result($insres->[0], $insres->[1],
                            {item_id=>$prog0});
        next unless $insres->[0] == 200;
        $added++;
        $content = $insres->[2]{text};
    }

    if ($added) {
        my $writeres = _write_f($args{file}, $content);
        return err("Can't write", $writeres) if $writeres->[0] != 200;
    }

    $envres->as_struct;
}

sub _delete {
    my %args = @_;
    my $readres = _read_parse_f($args{file});
    return err("Can't read entries", $readres) if $readres->[0] != 200;

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

sub _clean {
    require File::Which;

    my %args = @_;
    _delete(
        criteria => sub {
            my $names = shift;
            # remove if none of the names in complete command are in PATH
            for my $name (@{ $names }) {
                if (File::Which::which($name)) {
                    return 0;
                }
            }
            return 1;
        },
        %args,
    );
}

1;
# ABSTRACT: Backend for bash-completion-prog script
