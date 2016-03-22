package Test2::Tools::EventDumper;
use strict;
use warnings;

our $VERSION = '0.000002';

use Carp qw/croak/;
use Scalar::Util qw/blessed/;

our @EXPORT = qw/dump_event dump_events/;
use base 'Exporter';

my %DEFAULTS = (
    qualify_functions   => 0,
    paren_functions     => 0,
    use_full_event_type => 0,
    show_empty          => 0,
    add_line_numbers    => 0,
    call_when_can       => 1,
    convert_trace       => 1,

    field_order => {
        name           => 1,
        pass           => 2,
        effective_pass => 3,
        todo           => 4,
        max            => 5,
        directive      => 6,
        reason         => 7,
        trace          => 9999,
    },
    array_sort_order => 10000,
    other_sort_order => 9000,

    include_fields => undef,
    exclude_fields => {buffered => 1, nested => 1},

    indent_sequence => '    ',

    adjust_filename => sub {
        my $file = shift;
        $file =~ s{^.*[/\\](t|lib)[/\\]}{}g;
        return "match qr{\\Q$file\\E\$}";
    },
);

sub dump_event {
    my ($event, %settings) = @_;

    croak "No event to dump"
        unless $event;

    croak "dump_event() requires a Test2::Event (or subclass) instance, Got: $event"
        unless blessed($event) && $event->isa('Test2::Event');

    my $settings = keys %settings ? parse_settings(\%settings) : \%DEFAULTS;

    my $out = do_event_dump($event, $settings);
    $out =~ s/\s+$//msg;

    if ($settings->{add_line_numbers}) {
        my $line = 1;
        my $count = length(0 + scalar split /\n/, $out);
        $out =~ s/^/sprintf("L%0${count}i: ", $line++)/gmse;
    }

    return $out;
}

sub dump_events {
    my ($events, %settings) = @_;

    croak "No events to dump"
        unless $events;

    croak "dump_events() requires an array reference, Got: $events"
        unless ref($events) eq 'ARRAY';

    croak "dump_events() requires an array reference of Test2::Event (or subclasss) instances, some array elements are not Test2::Event instances."
        if grep { !$_ || !blessed($_) || !$_->isa('Test2::Event') } @$events;

    my $settings = keys %settings ? parse_settings(\%settings) : \%DEFAULTS;

    my $out = do_array_dump($events, $settings);
    $out =~ s/\s+$/\n/msg;

    if ($settings->{add_line_numbers}) {
        my $line = 1;
        my $count = length(0 + scalar split /\n/, $out);
        $out =~ s/^/sprintf("L%0${count}i: ", $line++)/gmse;
    }

    return $out;
}

sub parse_settings {
    my $settings = shift;

    my %out;
    my %clone = %$settings;

    for my $field (qw/field_order include_fields exclude_fields/) {
        next unless exists  $clone{$field}; # Nothing to do.
        next unless defined $clone{$field}; # Do not modify an undef

        # Remove it from the clone
        my $order = delete $clone{$field};

        croak "settings field '$field' must be either an arrayref or hashref, got: $order"
            unless ref($order) =~ m/^(ARRAY|HASH)$/;

        my $count = 1;
        $out{$field} = ref($order) eq 'HASH' ? $order : map { $_ => $count++ } @$order;
    }

    return {
        %DEFAULTS,
        %clone,
        %out,
    };
}

sub do_event_dump {
    my ($event, $settings) = @_;
    my $type = blessed($event);

    my ($ps, $pe) = ($settings->{qualify_functions} || $settings->{paren_functions}) ? ('(', ')') : (' ', '');
    my $qf = $settings->{qualify_functions} ? "Test2::Tools::Compare::" : "";

    my $start = "${qf}event${ps}";

    if (!$settings->{use_full_event_type} && $type =~ m/^Test2::Event::(.+)$/) {
        my $short = $1;
        $start .= $short =~ m/\W/ ? "'$short'" : $short;
    }
    else {
        $start .= "'+$type'";
    }

    $start .= " => sub {\n";

    my $nest = "";
    my @fields = grep { $_ !~ m/^_/ } keys %$event;

    push @fields => keys %{$settings->{include_fields}}
        if $settings->{include_fields};

    my %seen;
    @fields = grep { !$seen{$_}++ } @fields;

    @fields = sort {
        my $a_has_array = ref($event->{$a}) eq 'ARRAY';
        my $b_has_array = ref($event->{$b}) eq 'ARRAY';

        my $av = $a_has_array ? $settings->{array_sort_order} : ($settings->{field_order}->{$a} || $settings->{other_sort_order});
        my $bv = $b_has_array ? $settings->{array_sort_order} : ($settings->{field_order}->{$b} || $settings->{other_sort_order});

        return $av <=> $bv || $a cmp $b;
    } @fields;

    my $DNE = {};
    for my $field (@fields) {
        unless (exists $event->{$field}) {
            $nest .= "${qf}field${ps}'$field' => DNE()${pe};\n" if $settings->{show_empty};
            next;
        }

        my $val = $event->{$field};
        next unless $settings->{show_empty} || (defined($val) && length($val));

        my $func = ($settings->{call_when_can} && $event->can($field)) ? 'call' : 'field';

        if ($settings->{convert_trace} && $field eq 'trace') {
            $nest .= "\n" if $nest;
            my $file = $settings->{adjust_filename}->($val->file);
            $nest .= "${qf}prop${ps}file => $file${pe};\n";
            $nest .= "${qf}prop${ps}line => '" . $val->line . "'${pe};\n";
        }
        elsif (ref($val)) {
            if (ref($val) eq 'ARRAY' && !grep { !$_->isa('Test2::Event') } @$val) {
                $nest .= "\n" if $nest;
                $nest .= "${qf}${func}${ps}$field => " . do_array_dump($val, $settings) . "${pe};\n";
            }
            else {
                $nest .= "${qf}${func}${ps}'$field' => T()${pe}; # Unknown value: " . (blessed($val) || ref($val)) . "\n";
            }
        }
        elsif(defined($val)) {
            my %match = ( '{' => '}', '(' => ')', '[' => ']', '/' => '/' );
            my ($s1) = grep { $val !~ m/\Q$_\E/ && ($_ ne "'" || $val !~ m/(\n|\r)/) } qw/' " { \/ [ (/;
            my $s2 = $match{$s1} || $s1;
            my $qq = $match{$s1} ? 'qq' : '';
            $val =~ s/\n/\\n/g;
            $val =~ s/\r/\\r/g;
            $nest .= "${qf}${func}${ps}'$field' => ${qq}${s1}${val}${s2}${pe};\n";
        }
        else {
            $nest .= "${qf}${func}${ps}'$field' => undef${pe};\n";
        }
    }
    $nest =~ s/^/$settings->{indent_sequence}/mg;

    return "${start}${nest}}${pe}";
}

sub do_array_dump {
    my ($array, $settings) = @_;

    my ($ps, $pe) = ($settings->{qualify_functions} || $settings->{paren_functions}) ? ('(sub ', ')') : (' ', '');
    my $qf = $settings->{qualify_functions} ? "Test2::Tools::Compare::" : "";

    my $out = "${qf}array${ps}\{\n";

    my $nest = "";
    my $not_first = 0;
    for my $event (@$array) {
        $nest .= "\n" if $not_first++;
        $nest .= do_event_dump($event, $settings) . ";\n"
    }
    $nest .= "${qf}end();\n";
    $nest =~ s/^/$settings->{indent_sequence}/mg;

    $out .= $nest;
    $out .= "}${pe}";

    return $out;
}

__END__

=pod

=encoding UTF-8

=head1 NAME

Test2::Tools::EventDumper - Tool for dumping Test2::Event structures.

=head1 DESCRIPTION

This tool allows you to dump L<Test2::Event> instances (including subclasses).
The dump format is the L<Test2::Tools::Compare> event DSL. There are many
configuration options available to tweak the output to meet your needs.

=head1 SYNOPSYS

    use strict;
    use warnings;
    use Test2::Bundle::Extended;
    use Test2::API qw/intercept/;

    use Test2::Tools::EventDumper;

    my $events = intercept {
        # Some events change depending on the harness (legacy Test::Builder
        # behavior).
        local $ENV{'HARNESS_IS_VERBOSE'} = '1';
        local $ENV{'HARNESS_ACTIVE'}     = '1';

        ok(1, 'a');
        ok(2, 'b');
    };

    my $dump = dump_events $events;
    print "$dump\n";

The above will print this:

    array {
        event Ok => sub {
            call 'name' => 'a';
            call 'pass' => '1';
            call 'effective_pass' => '1';

            prop file => match qr{\Qt/basic.t\E};
            prop line => '12';
        };

        event Ok => sub {
            call 'name' => 'b';
            call 'pass' => '1';
            call 'effective_pass' => '1';

            prop file => match qr{\Qt/basic.t\E};
            prop line => '13';
        };
        end();
    }

B<Note>: There is no newline at the end of the string, '}' is the last
character.

=head1 EXPORTS

=over 4

=item dump_event($event)

=item dump_event $event => ( option => 1 )

This can be used to dump a single event. The first argument must always be an
L<Test2::Event> instance.

All additional arguments are key/value pairs treated as dump settings. See the
L</SETTINGS> section for details.

=item dump_events($arrayref)

=item dump_events $arrayref => ( option => 1 )

This can be used to dump an arrayref of events. The first argument must always
be an arrayref full of L<Test2::Event> instances.

All additional arguments are key/value pairs treated as dump settings. See the
L</SETTINGS> section for details.

=back

=head1 SETTINGS

All settings are listed with their default values when possible.

=over 4

=item qualify_functions => 0

This will cause all functions such as C<array> and C<call> to be fully
qualified, turning them into C<Test2::Tools::Compare::array> and
C<Test2::Tools::Compare::call>. This also turns on the
C<< paren_functions => 1 >> option. which forces the use of parentheses.

=item paren_functions => 0

This forces the use of parentheses in functions.

Example:

    call 'foo' => sub { ... };

becomes:

    call('foo' => sub { ... });

=item use_full_event_type => 0

Normally events in the C<Test2::Event::> namespace are shortened to only
include the postfix part of the name:

    event Ok => sub { ... };

When this option is turned on the full event package will be used:

    event '+Test2::Event::Ok' => sub { ... };

=item show_empty => 0

Normally empty fields are skipped. Empty means any field that does not exist,
is undef, or set to ''. 0 does not count as empty. When this option is turned
on all fields will be shown.

=item add_line_numbers => 0

When this option is turned on, all lines will be prefixed with a label
containing the line number, for example:

    L01: array {
    L02:     event Ok => sub {
    L03:         call 'name' => 'a';
    L04:         call 'pass' => '1';
    L05:         call 'effective_pass' => '1';
    L06:
    L07:         prop file => match qr{\Qt/basic.t\E};
    L08:         prop line => '12';
    L09:     };
    L00:
    L01:     event Ok => sub {
    L12:         call 'name' => 'b';
    L13:         call 'pass' => '1';
    L14:         call 'effective_pass' => '1';
    L15:
    L16:         prop file => match qr{\Qt/basic.t\E};
    L17:         prop line => '13';
    L18:     };
    L19:     end();
    L20: }

These labels do not change the code in any meaningful way, it will still run in
C<eval> and it will still produce the same result. These labels can be useful
during debugging.

=item call_when_can => 1

This option is turned on by default. When this option is on the C<call()>
function will be used in favor of the C<field()> when the field name also
exists as a method for the event.

=item convert_trace => 1

This option is turned on by default. When this option is on the C<trace> field
is turned into 2 checks, one for line, and one for filename.

Example:

    prop file => match qr{\Qt/basic.t\E};
    prop line => '12';

Without this option trace looks like this:

    call 'trace' => T(); # Unknown value: Test2::Util::Trace

Which is not useful.

=item field_order => { ... }

This allows you to assign a sort weight to fields (0 is ignored). Lower values
are displayed first.

Here are the defaults:

    field_order => {
        name           => 1,
        pass           => 2,
        effective_pass => 3,
        todo           => 4,
        max            => 5,
        directive      => 6,
        reason         => 7,
        trace          => 9999,
    }

Anything not listed gets the value from the 'other_sort_order' parameter.

=item other_sort_order => 9000

This is the sort weight for fields not listed in C<field_order>.

=item array_sort_order => 10000

This is the sort weight for any field that contains an array of event objects.
For example the C<subevents> field in subtests.

=item include_fields => [ ... ]

Fields that should always be listed if present (or if 'show_empty' is true).
This is not set by default.

=item exclude_fields => [ ... ]

Fields that should never be listed. To override the defaults set this to a new
arrayref, or to undef to clear the defaults.

defaults:

    exclude_fields => [qw/buffered nested/]

=item indent_sequence => '    '

How to indent each level. Normally 4 spaces are used. You can set this to
C<"\t"> if you would prefer tabs. You can also set this to any valid string
with varying results.

=item adjust_filename => sub { ... }

This is used when the C<convert_trace> option is true. This should be a coderef
that modifies the filename to something portable. It should then return a
string to be inserted after C<< 'field' => >>.

Here is the default:

    sub {
        my $file = shift;
        $file =~ s{^.*[/\\](t|lib)[/\\]}{}g;
        return "match qr{\\Q$file\\E}";
    },

This default strips off most of the path from the filename, stopping after
removing '/lib/' or '/t/'. After stripping the filename it puts it into a
C<match()> check with the '\Q' and '\E' quoting construct to make it safer.

The default is probably adequate for most use cases.

=back

=head1 SOURCE

The source code repository for Test2-Tools-EventDumper can be found at
F<http://github.com/Test-More/Test2-Tools-EventDumper/>.

=head1 MAINTAINERS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 AUTHORS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 COPYRIGHT

Copyright 2016 Chad Granum E<lt>exodist7@gmail.comE<gt>.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See F<http://dev.perl.org/licenses/>

=cut
