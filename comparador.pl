#!/opt/perl-5.20.0/bin/perl

use strict;
use warnings;
use PHP::Include;
use CWB::CQP::More;
use Try::Tiny;
use CGI qw/:standard/;
use JSON;
my $JQUERY = 'jquery.js';

include_php_vars("/var/www/html/acesso/var_corpora.php");
#line 14
# put above the line number for this line, for decent error reporting.


our $DEBUG = 0;

my @default_distrs = qw.word lema pos temcagr pessnum gen func.;
my %corpus_distrs = ();
for my $c (keys %atr_extra) {
    $corpus_distrs{$c} = [ map { s/^DIST//; lc $_ } split /:/, $atr_extra{$c}];
    push @{$corpus_distrs{$c}} => $_ for @default_distrs;
}
our $json_data = encode_json \%corpus_distrs;

show_form();

if (param('lcorpo') && param('lquery') && param('ldistr') &&
    param('rcorpo') && param('rquery') && param('rdistr')) {
    if (exists($corpora{param('lcorpo')}) && exists($corpora{param('rcorpo')})) {
        _log() if param('log');
        print div({id=>'wait'}, img({src=>'aguarde.gif'}));
        compare( 
                 merge => param("merge") ? 1 : 0,
				 limit => param("limite"),
                 left => {
                          corpo => param("lcorpo"),
                          query => guess_query(param("lquery")),
                          distr => param("ldistr"),
                         },
                 right => {
                           corpo => param("rcorpo"),
                           query => guess_query(param("rquery")),
                           distr => param("rdistr"),
                          });
    }
    else {
        show_error("Corpo inválido");
    }
}

print full_footer();

exit 0; # just to say so...

sub compare {
    my %data = @_;
    my $error;

	if ($data{merge}) {
		my %left_results  = map {@$_} results(%{$data{left}});
		my %right_results = map {@$_} results(%{$data{right}});
		my %merge;
		for my $k (keys %left_results, keys %right_results) {
			$merge{$k} = [ $left_results{$k} || 0 , $right_results{$k} || 0 ];			
		}

		print div( { -id => 'results' },
			 _format( _limit($data{limit}, map { [ $_, $merge{$_}[0], $merge{$_}[1] ] } 
					  sort { $merge{$b}[0] + $merge{$b}[1] <=>
                             $merge{$a}[0] + $merge{$a}[1] } keys %merge  ))
		);
    } else {
        print div({-id=>'results'},
                  div({-id=>'results-left'}, 
                      _format(_limit($data{limit}, results(%{$data{left}})))), "\n",
                  div({-id=>'results-right'},
                      _format(_limit($data{limit}, results(%{$data{right}})))), "\n",
                  hr({-style=>"display: none; clear: both;"}), "\n");
    }
}

sub _limit {
	my $limit = shift @_;
	return grep { _sum( @$_[1..$#$_] ) >= $limit } @_;
}

sub _sum {
    my $tot = 0;
    $tot += $_ for @_;
	$tot; 
}

sub results {
    my %data = @_;
    my ($cqp, $error);

    my $tipo_dist = $data{query} =~ /\@/ ? "collocate" : "match";

    $data{distr} =~ s/SOURCE/ori/;
    $data{distr} = lc($data{distr});

    try {
        $cqp = CWB::CQP::More->new('-r /home/registo');
        $cqp->change_corpus($data{corpo});
    } catch {
        $error = $_;
    };
    return show_error($error) if $error;

    $cqp->set(ps => $iddoc{$data{corpo}} || "p");

    try {
        $cqp->exec("A = $data{query};")
    } catch {
        $error = $_;
    };
    return show_error($error) if $error;

    my @answer = $cqp->exec_rows("group A $tipo_dist $data{distr};");
	return @answer;
}

sub _format {
    my @answer = @_;
    if (@answer) {
        return table({-style=>"width: 100%; "}, map { Tr(td(_protect($_))) } @answer);
    } else {
        return table({-style=>"width: 100%; "}, Tr(td(i("sem resultados"))));
    }
}

sub _protect {
    my $str = shift;
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    return $str;
}


sub show_form {
    print full_header();
    print start_form(-style => 'text-align: center', -action=>'comparador.pl');
    print hidden('log', 1);
    print table( {-id=> 'form'},
                 Tr(
                    th("Procurar: "),
                    td(textfield(-id   => 'lquery',
                                 -name => 'lquery',
                                 -size => 40)),
                    th("Procurar: "),
                    td(textfield(-id   => 'rquery',
                                 -name => 'rquery',
                                 -size => 40)),
                   ),
                 Tr(th("Corpo: "),
                    td(popup_menu(-id      => 'lcorpo',
                                  -name    => 'lcorpo',
                                  -default => 'CHAVE',
                                  -values  => [keys %corpora])),
                    th("Corpo: "),
                    td(popup_menu(-id      => 'rcorpo',
                                  -name    => 'rcorpo',
                                  -default => 'CHAVE',
                                  -values  => [keys %corpora])),
                   ),
                 Tr(th("Distribuir por: "),
                    td(popup_menu(-id      => 'ldistr',
                                  -name    => 'ldistr',
                                  -default => 'word',
                                  -values  => [])),
                    th("Distribuir por: "),
                    td(popup_menu(-id      => 'rdistr',
                                  -name    => 'rdistr',
                                  -default => 'word',
                                  -values  => [])),
                   ));
    print div({-style=>"margin-bottom: 15px; align: center"}, 
                checkbox(-name=>'merge', -checked=>0, value=>'merge', -label=>"fundir numa única tabela"));
	print div({-style=>"margin-bottom: 15px; align: center"},
                "Limite mínimo de frequência ", textfield(-name=>'limite', -value=>'0'));
    print submit(-id => 'procurar', -disabled => 'disabled',
                 -name => 'bt', -value => ' procurar ');
    print end_form;
}

## ... HTML auxiliary functions ... ... ... ... ... ... ... ... ... ... ... ... ... ... ...

sub show_error {
    print h3("Erro!");
    if (@_) {
        print join("\n", map { p($_) } @_ );
    } else {
        print "Acesso ilegal.";
    }
    return 1;
}

sub full_footer {
    join("", "</div>", end_html);
}

sub full_header {
    join("",
         header,
         start_html( -title  => 'Comparador',
                     -style  => { 'src'=>'comparador.css'},
                     -script => [
                                 { -language => 'JavaScript',
                                   -src =>  $JQUERY },
                                 { -language => 'JavaScript',
                                   -code => JS() },
                                ]),
         div({-id=>"linguateca"},
    	div(a({-href=>"http://linguateca.pt"}, "Linguateca"), 
            a({-href=>"http://linguateca.pt/ACDC"}, "AC/DC"),
            a({-href=>"ajuda.html"},"Ajuda")),
         h1('Comparador')),
         "<div id='content'>",
        );
}


sub JS {
    my $str = "var corpora_attrs = ".$json_data . ";\n" . <<'EOJS';

 var lcorpus_changed = false;
 var rcorpus_changed = false;
 var ldistr_changed = false;
 var rdistr_changed = false;

 $(document).ready( function() {

           $('#wait').css('display', 'none');
           $('#procurar').removeAttr('disabled');

       update_attributes('lcorpo', 'ldistr');
       update_attributes('rcorpo', 'rdistr');
EOJS

    if (param('ldistr')) {
        $str .= "       \$('#ldistr').val('" . param('ldistr') ."');";
    }
    if (param('rdistr')) {
        $str .= "       \$('#rdistr').val('" . param('rdistr') ."');";
    }

    $str .= <<'EOJS';

       $('#lcorpo').change( function() {
             lcorpus_changed = true;
             sync_corpus();
             update_attributes('lcorpo', 'ldistr');
       } );
       $('#rcorpo').change( function() {
             rcorpus_changed = true;
             sync_corpus();
             update_attributes('rcorpo', 'rdistr');
       } );

       $('#lquery').change( function() { sync_query(); } );
       $('#rquery').change( function() { sync_query(); } );

       $('#ldistr').change( function() {
             ldistr_changed = true;
             sync_distr();
       } );
       $('#rdistr').change( function() {
             rdistr_changed = true;
             sync_distr();
        } );
 });

 function sync_query() {
    if ($('#lquery').val() && !$('#rquery').val()) {
        $('#rquery').val( $('#lquery').val() );
    }
    if ($('#rquery').val() && !$('#lquery').val()) {
        $('#lquery').val( $('#rquery').val() );
    }
 }

 function sync_corpus() {
    if (lcorpus_changed && !rcorpus_changed) {
        $('#rcorpo').val( $('#lcorpo').val() );
        update_attributes('rcorpo', 'rdistr');
    }
    if (!lcorpus_changed && rcorpus_changed) {
        $('#lcorpo').val( $('#rcorpo').val() );
        update_attributes('lcorpo', 'ldistr');
    }
 }

 function sync_distr() {
    if ($('#rcorpo').val() == $('#lcorpo').val()) {
       if (ldistr_changed && !rdistr_changed) {
           $('#rdistr').val( $('#ldistr').val() );
       }
       if (!ldistr_changed && rdistr_changed) {
           $('#ldistr').val( $('#rdistr').val() );
       }
    }
 }

 function update_attributes( corpo_id, distr_id ) {
    var corpo = $('#' + corpo_id).val();
    var attributes = corpora_attrs[corpo];
    $('option', '#' + distr_id).remove();
    var ops = $('#' + distr_id).attr('options');
    $.each(attributes, function(index, element) {
                                       ops[ops.length] = new Option(element, element); });
    $('#' + distr_id).val('word');
 }
EOJS

  return $str;
}


sub my_sort {
    my ($a, $b) = @_;

    my $size  = min(scalar(@$a), scalar(@$b));
    my $res   = 0;
    my $i     = 0;
    while ($i < $size - 1 && !$res) {
        $res = $a->[$i] cmp $b->[$i];
        ++$i;
    }
    return $res;
}

sub min { $_[0] > $_[1] ? $_[1] : $_[0] }

sub guess_query {
    my $query = shift;
    if ($query !~ /"/) {
        $query =~ s/^\s*/[word=\"/;
        $query =~ s/\s*$/\"]/;
        $query =~ s/\s+/\"] [word=\"/;
    }
    return $query;
}

sub _log {
    open LOG, ">>:utf8", "comparador.log" or return;
    my $date = localtime;
    printf LOG "[$date|%s] %s // %s // %s // %s // %s // %s\n",
      $ENV{REMOTE_ADDR},
        param('lquery'), param('lcorpo'), param('ldistr'),
          param('rquery'), param('rcorpo'), param('rdistr');
    close LOG;
}
