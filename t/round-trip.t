use strict;
use warnings;
use Test2::Bundle::Extended;
use Test2::API qw/intercept/;

use Test2::Tools::EventDumper;

my $events = intercept {
    ok(1, 'a');
    ok(2, 'b');

    ok(0, 'fail');

    subtest foo => sub {
        ok(1, 'a');
        ok(2, 'b');
    };

    note "XXX";

    diag "YYY";
};

# To test show_empty's 'undef' rendering
$events->[1]->{name} = undef;

##############################################
#                                            #
# NOTE: Adding optins to this list increases #
# the number of tests EXPONENTIALLY!         #
#                                            #
##############################################
my $NULL = {};
my %options = (
    add_line_numbers    => [0, 1],
    paren_functions     => [0, 1],
    qualify_functions   => [0, 1],
    use_full_event_type => [0, 1],
    show_empty          => [0, 1],
    call_when_can       => [0, 1],
    convert_trace       => [0, 1],

    include_fields  => [$NULL, { name => 1 }],
    exclude_fields  => [$NULL, { pass => 1 }],
    adjust_filename => [$NULL, sub { 'T()' }],

    indent_sequence => [$NULL, "\t", ''],
);
##############################################

# Create all possible combinations
my @sets = {};
for my $opt (sort keys %options) {
    my $vals  = $options{$opt};
    my @start = @sets;
    @sets = ();
    for my $v (@$vals) {
        for my $s (@start) {
            push @sets => (ref($v) && $v == $NULL) ? {%$s} : {%$s, $opt => $v};
        }
    }
}

# Test dumping the entire structure
for my $set (@sets) {
    my $dump = dump_events $events => %$set;

    my $check = eval $dump;
    unless($check) {
        my $err = $@;
        fail;
        my $line = 1;
        my $count = length(0 + scalar split /\n/, $dump);
        $dump =~ s/^/sprintf("%0${count}i: ", $line++)/gmse;
        diag $dump;
        warn $err;
        next;
    }

    is(
        $events,
        $check,
    ) || diag $dump;
}

# Test dumpting the first event
for my $set (@sets) {
    my $dump = dump_event $events->[0] => %$set;

    my $check = eval $dump;
    unless($check) {
        my $err = $@;
        fail;
        my $line = 1;
        my $count = length(0 + scalar split /\n/, $dump);
        $dump =~ s/^/sprintf("%0${count}i: ", $line++)/gmse;
        diag $dump;
        warn $err;
        next;
    }

    is(
        $events->[0],
        $check,
    ) || diag $dump;
}

done_testing;
