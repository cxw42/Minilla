package Minilla::Release::UploadToCPAN;
use strict;
use warnings;
use utf8;
use ExtUtils::MakeMaker qw(prompt);

use Minilla::Util qw(require_optional);
use Minilla::Logger;

sub init {
    require_optional('CPAN/Uploader.pm',
        'Release engineering');
}

sub run {
    my ($self, $project, $opts) = @_;

    my $work_dir = $project->work_dir();
    my $tar = $work_dir->dist;

    if ($opts->{dry_run} || $ENV{FAKE_RELEASE}) {
        infof("Dry run. You don't need the module upload to CPAN\n");
    } elsif ($project->config->{release}->{do_not_upload_to_cpan}) {
        infof("You disabled CPAN uploading feature in minil.toml.\n");
    } else {
        infof("Upload to CPAN\n");

        my $pause_config = ($opts->{pause_config})          ? $opts->{pause_config}
            : ($project->config->{release}->{pause_config}) ? $project->config->{release}->{pause_config}
            :                                                 undef;
        my $config = CPAN::Uploader->read_config_file($pause_config);

        if(!$config->{password} && -t STDIN && -t STDOUT) {
            # Prompt for password if not in .pause
            eval {
                require Term::ReadKey;
                # Prompt for the password.
                # The following is from CPAN-Uploader's cpan-upload script.
                local $| = 1;
                print "PAUSE Password (don't worry - we're not uploading yet): ";
                Term::ReadKey::ReadMode('noecho');
                $config->{password} = <STDIN>;
                Term::ReadKey::ReadMode('restore');
                chomp $config->{password} if defined $config->{password};
                print "\n";
            };

            if($@) { die <<EOF }
Your password is not in the ~/.pause file, and I can't prompt you for it.
Please install the Term::ReadKey module if it isn't already, and try again.
EOF

        }

        if (!$config || !$config->{user} || !$config->{password}) {
            die <<EOF

I need a PAUSE username and password.
Perhaps:
 - Missing ~/.pause file?
 - ~/.pause file in the wrong format?
   The format is:

    user {{YOUR_PAUSE_ID}}
    password {{YOUR_PAUSE_PASSWORD}}

EOF
        }

        if ($opts->{trial}) {
            my $orig_file = $tar;
            $tar =~ s/\.(tar\.gz|tgz|tar.bz2|tbz|zip)$/-TRIAL.$1/
            or die "Distfile doesn't match supported archive format: $orig_file";
            infof("renaming $orig_file -> $tar for TRIAL release\n");
            rename $orig_file, $tar or errorf("Renaming $orig_file -> $tar failed: $!\n");
        }

        PROMPT: while (1) {
            my $answer = prompt("Release $tar to " . ($config->{upload_uri} || 'CPAN') . ' ? [y/n] ');
            if ($answer =~ /y/i) {
                last PROMPT;
            } elsif ($answer =~ /n/i) {
                errorf("Giving up!\n");
            } else {
                redo PROMPT;
            }
        }

        my $uploader = CPAN::Uploader->new(+{
            tar => $tar,
            %$config
        });
        $uploader->upload_file($tar);
    }

    unlink($tar) unless Minilla->debug;
}

1;

