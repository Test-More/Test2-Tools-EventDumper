use strict;
use warnings;
use Test2::Bundle::Extended;
use Test2::API qw/intercept/;

use Test2::Tools::EventDumper;

my $events = intercept {
    local $ENV{'HARNESS_IS_VERBOSE'} = '1';
    local $ENV{'HARNESS_ACTIVE'}     = '1';

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

my $dump = dump_events $events;
#print "$dump\n";

is("$dump\n", <<'EOT', "Output matches expectations");
array {
    event Ok => sub {
        call 'name' => 'a';
        call 'pass' => '1';
        call 'effective_pass' => '1';

        prop file => match qr{\Qt/basic.t\E$};
        prop line => '12';
    };

    event Ok => sub {
        call 'name' => 'b';
        call 'pass' => '1';
        call 'effective_pass' => '1';

        prop file => match qr{\Qt/basic.t\E$};
        prop line => '13';
    };

    event Ok => sub {
        call 'name' => 'fail';
        call 'pass' => '0';
        call 'effective_pass' => '0';

        prop file => match qr{\Qt/basic.t\E$};
        prop line => '15';
    };

    event Diag => sub {
        call 'message' => "Failed test 'fail'\nat t/basic.t line 15.\n";

        prop file => match qr{\Qt/basic.t\E$};
        prop line => '15';
    };

    event Subtest => sub {
        call 'name' => 'foo';
        call 'pass' => '1';
        call 'effective_pass' => '1';
        call 'buffered' => '1';

        prop file => match qr{\Qt/basic.t\E$};
        prop line => '20';

        call subevents => array {
            event Ok => sub {
                call 'name' => 'a';
                call 'pass' => '1';
                call 'effective_pass' => '1';
                call 'nested' => '1';

                prop file => match qr{\Qt/basic.t\E$};
                prop line => '18';
            };

            event Ok => sub {
                call 'name' => 'b';
                call 'pass' => '1';
                call 'effective_pass' => '1';
                call 'nested' => '1';

                prop file => match qr{\Qt/basic.t\E$};
                prop line => '19';
            };

            event Plan => sub {
                call 'max' => '2';
                call 'nested' => '1';

                prop file => match qr{\Qt/basic.t\E$};
                prop line => '20';
            };
            end();
        };
    };

    event Note => sub {
        call 'message' => 'XXX';

        prop file => match qr{\Qt/basic.t\E$};
        prop line => '22';
    };

    event Diag => sub {
        call 'message' => 'YYY';

        prop file => match qr{\Qt/basic.t\E$};
        prop line => '24';
    };
    end();
}
EOT


done_testing;
