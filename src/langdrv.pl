#!/usr/bin/perl
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(basename dirname);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use Getopt::Long qw(GetOptions);
use POSIX qw(uname);

Getopt::Long::Configure(qw(gnu_getopt no_auto_abbrev no_ignore_case));

my $arch = 'i386';
my $output;
my $emit_asm = 0;
my $compile_only = 0;
my $debug_info = 0;
my $verbose = 0;
my $help = 0;
my ($lpp_option, $langc_option, $cc_option);

# langc itself uses GCC's single-dash spelling, so accept it here too even
# though Getopt::Long in GNU mode reserves long options for a double dash.
for my $arg (@ARGV) {
    $arg =~ s/\A-march(?==|\z)/--march/;
}

sub usage {
    my ($fh, $status) = @_;
    print {$fh} <<'USAGE';
Usage: langdrv.pl [options] file...

Compile and link UPLNC sources. Inputs may be .e source files, assembler files,
or object files (object files are accepted when linking).

Options:
  -march=ARCH    Target: i386, x86_64, arm64, riscv64, or mips64
  -o FILE        Write the output to FILE (default when linking: a.out)
  -S             Compile .e sources to assembly without assembling
  -c             Compile .e/.s inputs to object files without linking
  -g             Emit source line info (.file/.loc) so gdb can map addresses
  -v, --verbose  Print commands as they are executed
  --lpp FILE     Use FILE as the preprocessor
  --langc FILE   Use FILE as the compiler
  --cc FILE      Use FILE as the assembler/linker driver
  -h, --help     Show this help

Tool overrides may also be set with UPLNC_LPP, UPLNC_LANGC, and UPLNC_CC.
USAGE
    exit $status;
}

sub fail {
    print STDERR "langdrv: $_[0]\n";
    exit 1;
}

GetOptions(
    'march=s'       => \$arch,
    'o=s'           => \$output,
    'S'             => \$emit_asm,
    'c'             => \$compile_only,
    'g'             => \$debug_info,
    'v|verbose'     => \$verbose,
    'lpp=s'         => \$lpp_option,
    'langc=s'       => \$langc_option,
    'cc=s'          => \$cc_option,
    'h|help'        => \$help,
) or usage(*STDERR, 1);

usage(*STDOUT, 0) if $help;
fail('-S and -c cannot be used together') if $emit_asm && $compile_only;
fail('no input files') unless @ARGV;

my %valid_arch = map { $_ => 1 } qw(i386 x86_64 arm64 riscv64 mips64);
fail("unsupported target '$arch'") unless $valid_arch{$arch};
fail('-o with -S or -c requires exactly one input')
    if defined($output) && ($emit_asm || $compile_only) && @ARGV != 1;

sub find_on_path {
    my ($name) = @_;
    return unless defined $name && length $name;
    if (File::Spec->file_name_is_absolute($name) || $name =~ m{/}) {
        return -x $name ? abs_path($name) : undef;
    }
    for my $dir (File::Spec->path()) {
        my $candidate = File::Spec->catfile($dir, $name);
        return $candidate if -x $candidate;
    }
    return;
}

sub require_tool {
    my ($description, $override, @defaults) = @_;
    if (defined $override && length $override) {
        my $path = find_on_path($override);
        fail("cannot execute $description '$override'") unless defined $path;
        return $path;
    }
    for my $candidate (@defaults) {
        my $path = find_on_path($candidate);
        return $path if defined $path;
    }
    fail("cannot find $description; build the stage-0 tools or provide its path");
}

sub shell_quote {
    my ($word) = @_;
    return "''" if $word eq '';
    return $word if $word =~ m{\A[-+./:=_,A-Za-z0-9]+\z};
    $word =~ s/'/'"'"'/g;
    return "'$word'";
}

sub run_command {
    my ($stdin, $stdout, @command) = @_;
    if ($verbose) {
        my $shown = join(' ', map { shell_quote($_) } @command);
        $shown .= ' < ' . shell_quote($stdin) if defined $stdin;
        $shown .= ' > ' . shell_quote($stdout) if defined $stdout;
        print STDERR "+ $shown\n";
    }

    my $pid = fork();
    fail('fork failed: ' . $!) unless defined $pid;
    if ($pid == 0) {
        if (defined $stdin) {
            open(STDIN, '<', $stdin) or do {
                print STDERR "langdrv: cannot read '$stdin': $!\n";
                exit 126;
            };
        }
        if (defined $stdout) {
            open(STDOUT, '>', $stdout) or do {
                print STDERR "langdrv: cannot write '$stdout': $!\n";
                exit 126;
            };
        }
        exec {$command[0]} @command or do {
            print STDERR "langdrv: cannot execute '$command[0]': $!\n";
            exit 126;
        };
    }

    waitpid($pid, 0);
    if ($? == -1) {
        fail("could not wait for '$command[0]': $!");
    }
    if ($? & 127) {
        my $signal = $? & 127;
        fail("'$command[0]' terminated by signal $signal");
    }
    return $? >> 8;
}

sub command_succeeds_silently {
    my (@command) = @_;
    my $pid = fork();
    fail('fork failed while probing the toolchain: ' . $!) unless defined $pid;
    if ($pid == 0) {
        open(STDOUT, '>', File::Spec->devnull()) or exit 126;
        open(STDERR, '>', File::Spec->devnull()) or exit 126;
        exec {$command[0]} @command or exit 126;
    }
    waitpid($pid, 0);
    return $? == 0;
}

sub output_name {
    my ($input, $suffix) = @_;
    my $name = basename($input);
    $name =~ s/\.[^.]+\z//;
    return $name . $suffix;
}

sub staged_output {
    my ($target) = @_;
    my $directory = dirname($target);
    my ($fh, $temporary);
    eval {
        ($fh, $temporary) = tempfile('.uplnc-output-XXXXXX',
                                     DIR => $directory, UNLINK => 1);
    };
    fail("cannot create output beside '$target': $@") if $@;
    close($fh) or fail("cannot prepare output '$target': $!");
    return $temporary;
}

sub commit_output {
    my ($temporary, $target) = @_;
    rename($temporary, $target)
        or fail("cannot install output '$target': $!");
}

my @input_kind;
my $needs_frontend = 0;
for my $input (@ARGV) {
    fail("input file '$input' does not exist") unless -f $input;
    my $kind;
    if ($input =~ /\.e\z/i) {
        $kind = 'source';
        $needs_frontend = 1;
    } elsif ($input =~ /\.[sS]\z/) {
        $kind = 'assembly';
    } elsif ($input =~ /\.o\z/i) {
        $kind = 'object';
    } else {
        fail("unsupported input '$input' (expected .e, .s, .S, or .o)");
    }
    fail("-S accepts only .e source files") if $emit_asm && $kind ne 'source';
    fail("-c does not accept object input '$input'")
        if $compile_only && $kind eq 'object';
    push @input_kind, $kind;
}

my $script = abs_path($0) || $0;
my $repo = abs_path(File::Spec->catdir(dirname($script), '..'));
my $build = File::Spec->catdir($repo, 'transpiler', 'build');
my ($lpp, $langc);
if ($needs_frontend) {
    $lpp = require_tool(
        'UPLNC preprocessor',
        defined($lpp_option) ? $lpp_option : $ENV{UPLNC_LPP},
        File::Spec->catfile($build, 'lpp1'), 'lpp1'
    );
    $langc = require_tool(
        'UPLNC compiler',
        defined($langc_option) ? $langc_option : $ENV{UPLNC_LANGC},
        File::Spec->catfile($build, 'langc'), 'langc'
    );
}

my $tmpdir = tempdir('uplnc-driver-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $sequence = 0;

sub compile_source {
    my ($source, $assembly) = @_;
    my $preprocessed = File::Spec->catfile($tmpdir, 'input-' . $sequence++ . '.i');
    my $rc = run_command(undef, $preprocessed, $lpp, $source);
    fail("preprocessing '$source' failed (exit $rc)") if $rc != 0;
    my @langc_args = ("-march=$arch");
    push @langc_args, '-g' if $debug_info;
    $rc = run_command($preprocessed, $assembly, $langc, @langc_args);
    fail("compiling '$source' failed (exit $rc)") if $rc != 0;
}

if ($emit_asm) {
    my %outputs;
    for my $i (0 .. $#ARGV) {
        my $assembly = defined($output) ? $output : output_name($ARGV[$i], '.s');
        fail("multiple inputs would write '$assembly'") if $outputs{$assembly}++;
        my $temporary = staged_output($assembly);
        compile_source($ARGV[$i], $temporary);
        commit_output($temporary, $assembly);
    }
    exit 0;
}

my @host = uname();
my $machine = $host[4] || '';
my $cc_override = defined($cc_option) ? $cc_option : $ENV{UPLNC_CC};
my ($default_cc, @assemble_flags, @link_flags);
if ($arch eq 'i386') {
    $default_cc = 'gcc';
    @assemble_flags = ('-m32');
    @link_flags = ('-m32', '-no-pie');
} elsif ($arch eq 'x86_64') {
    $default_cc = 'gcc';
    @link_flags = ('-no-pie');
} elsif ($arch eq 'arm64') {
    $default_cc = $machine eq 'aarch64' ? 'gcc' : 'aarch64-linux-gnu-gcc';
    @link_flags = $machine eq 'aarch64' ? ('-no-pie') : ('-static');
} elsif ($arch eq 'riscv64') {
    $default_cc = $machine eq 'riscv64' ? 'gcc' : 'riscv64-linux-gnu-gcc';
    @link_flags = $machine eq 'riscv64' ? ('-no-pie') : ('-static');
} else {
    $default_cc = $machine eq 'mips64' ? 'gcc' : 'mips64-linux-gnuabi64-gcc';
    @assemble_flags = ('-mno-abicalls', '-fno-pic', '-G', '0');
    @link_flags = (@assemble_flags, $machine eq 'mips64' ? '-no-pie' : '-static');
}
my $cc;
if ($arch eq 'i386' && !$compile_only) {
    my @candidates = defined($cc_override) && length($cc_override)
        ? ($cc_override)
        : qw(gcc gcc-14 gcc-13 gcc-12 gcc-11 gcc-10 gcc-9);
    my $probe_source = File::Spec->catfile($tmpdir, 'm32-probe.c');
    my $probe_output = File::Spec->catfile($tmpdir, 'm32-probe');
    open(my $probe, '>', $probe_source)
        or fail("cannot create i386 toolchain probe: $!");
    print {$probe} "int main(void){return 0;}\n";
    close($probe) or fail("cannot write i386 toolchain probe: $!");
    for my $candidate (@candidates) {
        my $path = find_on_path($candidate);
        next unless defined $path;
        if (command_succeeds_silently($path, '-m32', '-x', 'c',
                                      $probe_source, '-o', $probe_output)) {
            $cc = $path;
            last;
        }
    }
    fail('no working i386 linker found (install gcc-multilib / libc6-dev-i386)')
        unless defined $cc;
} else {
    $cc = require_tool('assembler/linker', $cc_override, $default_cc);
}

if ($compile_only) {
    my %outputs;
    for my $i (0 .. $#ARGV) {
        my $object = defined($output) ? $output : output_name($ARGV[$i], '.o');
        fail("multiple inputs would write '$object'") if $outputs{$object}++;
        my $assembly = $ARGV[$i];
        if ($input_kind[$i] eq 'source') {
            $assembly = File::Spec->catfile($tmpdir, 'source-' . $sequence++ . '.s');
            compile_source($ARGV[$i], $assembly);
        }
        my $temporary = staged_output($object);
        my $rc = run_command(undef, undef, $cc, @assemble_flags,
                             '-c', $assembly, '-o', $temporary);
        fail("assembling '$ARGV[$i]' failed (exit $rc)") if $rc != 0;
        commit_output($temporary, $object);
    }
    exit 0;
}

my @link_inputs;
for my $i (0 .. $#ARGV) {
    if ($input_kind[$i] eq 'source') {
        my $assembly = File::Spec->catfile($tmpdir, 'source-' . $sequence++ . '.s');
        compile_source($ARGV[$i], $assembly);
        push @link_inputs, $assembly;
    } else {
        push @link_inputs, $ARGV[$i];
    }
}

my $executable = defined($output) ? $output : 'a.out';
my $temporary = staged_output($executable);
my $rc = run_command(undef, undef, $cc, @link_flags, @link_inputs, '-o', $temporary);
fail("linking '$executable' failed (exit $rc)") if $rc != 0;
commit_output($temporary, $executable);
exit 0;
