
    #   Compute statistics from a series of TIMEREZ reports
    #   copied and pasted from local chat.

    #   This program requires the Statistics::Descriptive
    #   package, which can be installed on Xubuntu systems
    #   with: apt-get install libstatistics-descriptive-perl

    use strict;
    use warnings;

    use Statistics::Descriptive;

    my $s = Statistics::Descriptive::Sparse->new();

    while (my $l = <>) {
        chomp($l);
        if ($l =~ m/time:\s+([\d\.]+)\s/) {
            my $time = $1;
            $s->add_data($time);
        } else {
            print("Could not parse $l\n");
        }
    }

    printf("Mean time for %d measurements: %.4f seconds.\n",
        $s->count(), $s->mean());
    printf("  Variance: %.4f\n", $s->variance());
    printf("  Standard deviation: %.4f\n", $s->standard_deviation());
