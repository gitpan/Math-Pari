#! perl
# 	$rcs = ' $Id: testout.t,v 1.2 1997/09/22 10:13:37 ilya Exp ilya $ ' ;	

use Math::Pari qw(:DEFAULT pari_print :all);
use vars qw($x $y $z $k $t $q $a $u $j $l $name $other $n);
die "Need a path to a testout file" unless @ARGV;

$file = shift;
{
  open TO, "< $file" or die "open `$file': $!";
  local $/ = "\n? ";
  @tests = <TO>;
  close TO or die "close: $!";
}

$mess = shift @tests;		# Messages
pop @tests;			# \q
$tests = @tests;

print "1..$tests\n";

prec($3 || $1, 1) if $mess =~ /realprecision = (\d+) significant digits( \((\d+) digits displayed\))?/;  

$| = 1;
@seen{qw(Pi I Euler getrand a x y z k t q u j l n v p name other mhbi a2 a1 a0 b0 b1
	 acurve bcurve ccurve cmcurve tcurve mcurve ma mpoints)} 
  = (' ', ' ', ' ', ' ', ('$') x 100);
for (keys %seen) {
  $$_ = PARI($_);
}
$seen{'random'} = ' ';
$DEFAULT = undef;

# Some of these are repeated below (look for XXXX), since they cause
# an early interpretation of unquoted args
@not_yet_defined{qw(
    type
  )} = (1) x 10000;

if ($file =~ /plot|graph|all/) {
  eval { link_gnuplot() };
  if ($@ =~ m%^Can't locate Term/Gnuplot.pm in \@INC%) {
    print STDERR "# Can't locate Term/Gnuplot.pm in \@INC, ignoring plotting\n";
    @not_yet_defined{qw(
      plotbox plotcolor plotcursor plotdraw ploth plothraw plotinit plotlines 
      plotmove plotpoints plotrline plotrmove plotrpoint psdraw psploth 
      psplothraw
      plotkill
    )} = (1) x 10000;
  } elsif ($@) {
    die $@;
  }
}

$started = 0;

main_loop:
for (@tests) {
  #print "Doing `$_'";
  1 while s/^\\\\.*\n//;	# Comment
  $bad = /^\\/;			# \precision = 
  $wasbadprint = /\b(plot)\b/;
  $wasprint = /\b((|p|tex)print(tex)?|plot)\b/;
  s/\s*\n\?\s*\Z// or die "Not terminated: `$_'\n";
  s/\A(\s*\?)+\s*//;
#  s/[^\S\n]+$//gm;
  s/\A(.*)\s*; $ \s*(\w+)\s*\(/$1;$2(/mx; # Continuation lines of questions
  # Special-case test nfields-3 with a wrapped question:
  s/\A(p2=.*\d{10})\n(7\n)/$1$2/;
  s/\A(.*)\s*$//m or die "No question: `$_'\n";
  $in = $1;
  1 while s/^\n//;		# Before warnings
  1 while s/^\s*\*+\s*warning.*\n?//i; # skip warnings
  if (s/^\s*\*+\s*(.*)//) {		# error
    process_error($in,$_,$1);
    next;
  }
  process_test($in, 'noans', []), next if /^$/; # Was a void 
#  s/^%\d+\s*=\s*// or die "Malformed answer: $_" unless $bad or $wasprint;
  if ($_ eq '' or $wasprint) {	# Answer is multiline
#    @ans = $_ eq '' ? () : ($_) ;
#    while (<>) {
#      last if /^\?\s+/;
#      next if /^$/;
#      chomp;
#      push @ans, $_;
#    }
    @ans = split "\n";
    if ($wasbadprint) {
      process_print($in, @ans);
    } elsif ($wasprint) {
      process_test($in, 'print', [@ans]);
    } else {
      process_test($in, 0, [@ans]);
    }
    next main_loop;
  }
  if ($bad) {
    process_set($in, $_);
  } else {
    process_test($in, 0, [$_]);
  }
}

sub format_matrix {
  my $in = shift;
  my @in = split /;/, $in;
  'PARImat_tr([[' . join('], [', @in) . ']])';
}

sub format_vvector {
  my $in = shift;
  $in =~ s/~\s*$//;
  "PARIcol($in)";
}

sub re_format {			# Convert PARI output to a regular expression
  my $in = join "\n", @_;
  $in = quotemeta $in;
  $in =~ s/\\\]\\\n\\\n\\\[/\\s*;\\s*/g; # row separator
  $in =~ s/\\\n/\\s*/g;
  $in =~ s/\\[ \t]/,?\\s*/g;
  $in
}

sub mformat {
  # if not matrix, join with \t
  return join("\t", @_) unless @_ > 1 and $_[0] =~ /^\[/;
  @_ = grep {!/^$/} @_;		# remove empty lines
  return join("\t", @_) if grep {!/^\s*\[.*\]\s*$/} @_;	# Not matrix
  #return join("\t", @_) if grep {!/^\s*\([^,]*,\s*$/} @_; # Extra commas
  map {s/^\s*\[(.*)\]\s*$/$1/} @_;
  my @arr = map { join ', ', split } @_;
  '[' . join('; ', @arr) . ']';
}

sub mformat_transp {
  return join("\t", @_) unless @_ > 1 and $_[0] =~ /^\[/;
  @_ = grep {!/^$/} @_;
  return join("\t", @_) if grep {!/^\s*\[.*\]\s*$/} @_;	# Not matrix
  #return join("\t", @_) if grep {!/^\s*\([^,]*,\s*$/} @_; # Extra commas
  map {s/^\s*\[(.*)\]\s*$/$1/} @_;
  my @arr = map { [split] } @_;
  my @out;
  my @dummy = ('') x @{$arr[0]};
  for my $ind (0..$#{$arr[0]}) {
    for my $subarr (@arr) {
      @$subarr > $ind or $subarr->[$ind] = ''; 
    }
    push @out, join ', ', map {$_->[$ind]} @arr;
  }
  '[' . join('; ', @out) . ']';
}

sub massage_floats {
  my $in = shift;
  $pre = shift || "16g";
  $in =~ s/(.\d*)\s+e/$1E/gi;	# 1.74 E-78
  $in =~ s/\b(\d+\.\d*(e[-+]?\d+)?|\d{10,})\b/sprintf "%.${pre}", $1/gei;
  $in;
}

sub o_format {
  my ($var,$power) = @_;
  return " PARI('O($var^$power)') " if defined $power;
  return " PARI('O($var)') ";
}

sub process_cond {
  my ($what, $cond, $then, $else, $initial) = @_;
  die if $initial =~ /Skip this/;
  # warn "Converting `$in'\n`$what', `$cond', `$then', `$else'\n";
  if (($what eq 'if') ne (defined $else)) {
    return "Skip this `$initial'";
  } elsif ($what eq 'if') {
    return "( ($cond) ? ($then) : ($else) )";
  } else {
    return "do { $what ($cond) { $then } }";
  }
}

sub process_test {
  my ($in, $noans, $out) = @_;
  my $doprint;
  $doprint = 1 if $noans eq 'print';
  my $was_prev = $prev;
  undef $prev;
  $c++;
  # First a trivial processing:
  $in =~ s/\b(\d+|[a-z]+\(\))\s*\\\s*(\d+(\^\d+)?)/ gdivent($1,$2)/g; # \
  $in =~ s/\b(\d+)\s*\\\/\s*(\d+)/ gdivround($1,$2)/g; # \/
  $in =~ s/\b(\w+)\s*!/ ifact($1)/g; # !
  $in =~ s/,\s*(?=,)/, \$DEFAULT /g;	# Default arguments?
  $in =~ s/^default\(realprecision,(.*)\)/\\p $1/; # Some cases of default()
  $in =~ s/^default\(seriesprecision,(.*)\)/\\ps $1/; # Some cases of default()
  $in =~ s/(\w+)\s*\\(\w+(\s*\^\s*\w+)?)/gdivent($1,$2)/g; # random\10^8
  $in =~ s/%(?!\s*[\[_\w])/\$was_prev/g; # foo(%)
  $in =~ s/\b(for)\s*\(\s*(\w+)=/&$1($2,/g; # for(x=1,13,print(x))
  if ($in =~ /^\\p\s*(\d+)/) {
    prec($1);
  } elsif ($in =~ /^\\ps\s*(\d+)/) {		# \\ for division unsupported
    sprec($1);
  } elsif ($in =~ /\\/) {		# \\ for division unsupported
    $c--;
    process_error($in, $out, '\\');
  } elsif ($in =~ /^(\w+)\s*\([^()]*\)\s*=/ and 0) { # XXXX Not implemented yet
    $c--;
    process_definition($1, $in);
  } elsif ($in =~ /[!\']/) {	# Factorial
    print "# `$in'\nok $c # Skipping (ifact/deriv)\n";
  } else {
    # work with "^", need to treat differently inside o()
    $in =~ s/\^/^^^/g;
    $in =~ s/\bo\(([^()^]*)(\^\^\^([^()]*))?\)/ o_format($1,$3) /gei;
    $in =~ s/\^\^\^/**/g;	# Now treat it outside of O()
    $in =~ s/\[([^\[\];]*;[^\[\]]*)\]/format_matrix($1)/ge; # Matrix
    $in =~ s/\[([^\[\];]*)\]\s*~/format_vvector($1)/ge; # Vertical vector
 eval {
    1 while $in =~ s/
	      \b (if|while|until) \( 
	      (
		(?:
		  [^(,)]+ 
		  (?=
		    [(,)]
		  )
		|
		  \( [^()]* \)
		)*		# One level of parenths supported
	      )
	      , 
	      (
		(?:
		  [^(,)]+ 
		  (?=
		    [(,)]
		  )
		|
		  \( [^()]* \)
		)*		# One level of parenths supported
	      )
	      (?:
		, 
		(
		  (?:
		    [^(,)]+ 
		    (?=
		      [(,)]
		    )
		  |
		    \( [^()]* \)
		  )*		# One level of parenths supported
		)
              )?
	      \)
	    /process_cond($1, $2, $3, $4, $in)/xge; # if(a,b,c)
 };
    if ($in =~ /\[[^\]]*;/) {	# Matrix
      print "# `$in'\nok $c # Skipping (matrix notation)\n";
      return;
    } elsif ($in =~ /Skip this `(.*)'/) {
      print "# `$1'\nok $c # Skipping (runaway conversion)\n";
      return;
    } elsif ($in =~ /&for\s*\([^\)]*$/) {	# Special case
      print "# `$in'\nok $c # Skipping (runaway input line)\n";
      return;
    } elsif ($in =~ /(^|[\(=,])%/) {
      print "# `$in'\nok $c # Skipping (history notation)\n";
      return;
    } elsif ($in =~ /
		      (
			\b 
			( if | goto | label | input | break
			  # | while | until
                          | gettime | default | sizebyte
                          # XXXX These need to be done ASAP:
			  | sumalt | prodinf 
                        )
			\b 
		      |
			(\w+) \s* \( \s* \w+ \s* \) = 
		      |
			\b install \s* \( \s* (\w+) \s* , [^()]* \)
		      |
			\b 
			(
			  my _
			)?
			p? print \( 
			( \[ | (1 ,)? PARImat )
		      |	  # Too many parens: will not be wrapped in sub{...}
		      	\b forprime .* \){4}
		      )
		    /x) {
      if (defined $3) {
	if (defined $userfun) {
	  $userfun .= "|$3";
	} else {
	  $userfun = $3;
	}
	print "# User function `$3'.\n";
      }
      if (defined $4) {
	if (defined $installed) {
	  $installed .= "|$4";
	} else {
	  $installed = $4;
	}
	print "# Installed function `$4'.\n";
      }
      # It is not clear why changevar gives a different answer in GP
      print "# `$in'\nok $c # Skipping (converting test for '$1' needs additional work)\n";
      return;
    } elsif ($userfun 
	     and $in =~ / \b ($userfun) \s* \( /x) {
      print "# `$in'\nok $c # Skipping (user function)\n";
      return;
    } elsif ($installed
	     and $in =~ / \b ($installed) \s* \( /x) {
      print "# `$in'\nok $c # Skipping (installed function)\n";
      return;
#    } elsif ($in =~ / \b ( sizebyte ) \b /x
#	     and $file !~ /will_fail/) {
#      # XXXX Will result in a wrong answer, but we moved these tests to a different
#      print "# `$in'\nok $c # Skipping (would fail, checked in different place)\n";
#      return;
    } elsif ($in =~ /\bget(heap|stack)\b/) { # Meaningless
      print "# `$in'\nok $c # Skipping meaningless\n";
      return;
    } elsif ($in =~ /\b(nonesuch now)\b/) {
      print "# `$in'\nok $c # Skipping (possibly FATAL $1)\n";
      return;
    }
    # Convert transposition
    $in =~ s/(\$?\w+(\([^()]*\))?|\[([^\[\]]+(?=[\[\]])|\[[^\[\]]*\])*\])~/mattranspose($1)/g;
    if ($in =~ /~/) {
      print "# `$in'\nok $c # Skipping (transpose notation)\n";
      return;
    }
    if ($in =~ /^\s*alias\s*\(\s*(\w+)\s*,\s*(\w+)\s*\)$/) {
      print "# Aliasing `$1' ==> `$2'\nok $c\n";
      *$1 = \&{$2};
      return;
    }
    if ($in !~ /\w\(/) { # No function calls
      # XXXX Primitive!
      # Constants: (.?) eats following + or - (2+3 ==> PARI(2)+PARI(3))
      $in =~ s/(^|\G|\W)([-+]?\d+(\.\d*)?)(.?)/$1 PARI($2) $4/g;
      # Big integer constants:
      $in =~ s/\bPARI\((\d{10,})\)/PARI('$1')/g;
    } elsif ($in =~ /\belllseries\b|\bbinomial\b|\*mathilbert\b/) { # high precision needed?
      # XXXX Primitive!
      # Substitute constants where they are not arguments to functions
      $in =~ s/(^|\G|\W)([-+]?\d+\.\d*)/$1 PARI('$2') /g;
      # Big integer constants:
      $in =~ s/\bPARI\((\d{10,})\)/PARI('$1')/g;
    } else {
      # Substitute big integer constants
      $in =~ s/(^|\G|\W)(\d{10,}(?!\.\d*))(.?)/$1 PARI('$2') $3/g;
      # Substitute division 
	$in =~ s/(^|[\-\(,\[])(\d+)\s*\/\s*(\d+)(?=$|[\),\]])/$1 PARI($2)\/PARI($3) /g;
    }
    # Substitute i= in loop commands
    if ($in !~ /\b(hermite|mathnf|until)\s*\(/) { # Special case, not loop-with-=
      $in =~ s/([\(,]\w+)=(?!=)/$1,/g;
    }
    # Substitute print
    $in =~ s/\b(|p|tex)print(tex|)\(/ 'my_' . $1 . $2 . 'print(1,' /ge;
    $in =~ s/\b(|p|tex)print1\(/ 'my_' . $1 . 'print(0,'/ge;
    $in =~ s/\b(eval|shift|sort)\(/&$1\(/g; # eval($y)
    # Recognize variables
    %seen_now = ();
    $in =~ s/(^|[;(])(\w+)(\s*=\s*)/$seen_now{$2} = '$'; $1 . '$' . $2 . $3/ge; # Assignment
    # Substitute variables (not before '^' - inside of 'o(x^17)'):
    $in =~ s/(^|[^\$])\b([a-zA-Z]\w*)\b(?!\s*[(^])/($1 || '') . ($seen{$2} || $seen_now{$2} || '') . $2/ge;
    # Die if did not substitute variables:
    while ($in =~ /(^|[^\$])\b([a-zA-Z]\w*)\b(?!\s*[\{\(^])/g) {
      print("# `$in'\nok $c # Skipping ($2 was not set)\n"), return
	unless $seen{$2} and $seen{$2} eq ' ' or $in =~ /\"/;
      # Let us hope that lines which contain '"' do not contain unset vars
    }
    # Simplify for the following conversion:
    $in =~ s/\brandom\(\)/random/g;
    # Sub-ify sum,prod,intnum
    1 while
      $in =~ s/
		(
		  \b 
		  (
		    sum 
		  |
		    intnum
		  |
		    prod (?: euler )?
		  ) \s*
		  \( 
		  (?:
		     (?:
		       [^(=,)]+ 
		       (?=
		         [(=,)]
		       )
		     |
		       \( [^()]+ \)
		     )		# One level of parenths supported
		  [,=]){3}		# $x,1,100
		)
		(?!\s*sub\s*\{)	# Skip already converted...
		(		# This follows after a comma on toplevel
		  (?:
		    [^(,)\[\]]+ 
		    (?=
		      [(,)\[\]]
		    )
		  |
		    \(		# One level of parenths
		    (?:
		      [^()]+ 
		      (?=
			[()]
		      )
		    |
		      \( [^()]+ \) # Second level of parenths
		    )*
		    \)
		  |
		    \[		# One level of brackets
		    (?:
		      [^\[\]]+ 
		      (?=
			[\[\]]
		      )
		    |
		      \[ [^\[\]]+ \] # Second level of brackets
		    )*
		    \]
		  )*		# Two levels of parenths supported
		)
		(?=
                  \)
                |
		  , [^(,)]+ \)
                )
	      /$1 sub{$3}/xg;
    # Sub-ify direuler
    1 while
      $in =~ s/
		(
		  \b 
		  (
		    direuler
		  ) \s*
		  \( 
		  (?:
		     (?:
		       [^(=,)]+ 
		       (?=
		         [(=,)]
		       )
		     |
		       \( [^()]+ \)
		     )		# One level of parenths supported
		  [,=]){3}		# $x,1,100
		)
		(?!\s*sub\s*\{)	# Skip already converted...
                (.*)
		(?=
                  \)
                )
	      /$1 sub{$3}/xg;
    # Do the rest
    1 while
      $in =~ s/
		(
		  \b 
		  (
		    solve 
		  |
		    (?:
		      post (?! plothraw \b)
		    )?
		    ploth \w* 
		  |
		    # sum \w* 
		    sum \w+
		  |
		    # prod \w* 
		    prodinf
		  |
		    v? vector v? 
		  |
		    matrix 
		  |
		    intgen 
		  #|
		  #  intnum 
		  |
		    intopen 
		  |
		    for \w*
		  )
		  \( 
		  (?:
		    [^()]+ 
		    (?=
		      [(,)]
		    )
		  |
		    \( [^()]+ \)
		  )+		# One level of parenths supported
		  ,
		)
		(?!\s*sub\s*\{)	# Skip already converted...
		(		# This follows after a comma on toplevel
		  (?:
		    [^(,)\[\]]+ 
		    (?=
		      [()\[\]]
		    )
		  |
		    \(		# One level of parenths
		    (?:
		      [^()]+ 
		      (?=
			[()]
		      )
		    |
		      \( [^()]+ \) # Second level of parenths
		    )*
		    \)
		  |
		    \[		# One level of brackets
		    (?:
		      [^\[\]]+ 
		      (?=
			[\[\]]
		      )
		    |
		      \[ [^\[\]]+ \] # Second level of brackets
		    )*
		    \]
		  )*		# Two levels of parenths supported
		)
		\)
	      /$1 sub{$3}\)/xg;
    # Convert 10*20 to integer
    $in =~ s/(\d+)(?=\*\*\d)/ PARI($1) /g;
    # Convert blah[3], blah()[3] to blah->[-1+3]
    $in =~ s/([\w\)])\[/$1 -> [-1+/g;
    # Workaround for &eval test:
    $in =~ s/\$y=\$x;&eval\b(.*)/PARI('y=x');&eval$1;\$y=\$x/;
    # Workaround for kill:
    $in =~ s/^kill\(\$(\w+)\);/kill('$1');\$$1=PARIvar '$1';/;
    print "# eval", ($noans ? "-$noans" : '') ,": $in\n";
    $printout = '';
    my $have_floats = ($in =~ /\d+\.\d*|\d{10,}/ 
		       or $in =~ /\b(zeta|bin|comprealraw|frac|lseriesell|powrealraw|legendre|suminf|forstep)\b/);
    # Remove the value from texprint:
    # pop @$out if $in =~ /texprint/ and @$out == 2;
    $res = eval "$in";
    $rres = $res;
    $rres = pari_print $res if defined $res and ref $res;
    my $re_out;
    if ($doprint) {
      if ($in =~ /my_texprint/) { # Special-case, assume one wrapped with \n
	$rout = join "", @$out, "\t";
      } else {
	$rout = join "\t", @$out, "";
      }
      if ($have_floats) {
	$printout = massage_floats $printout, "14f";
	$rout = massage_floats $rout, "14f";
      }
      # New wrapping code gets in the way:
      $printout =~ s/\s+/ /g;
      $rout =~ s/\s+/ /g;
    } else {
      # Special-case several tests in all.t
      if (($have_floats or $in =~ /^(sinh?|solve)\b/) and ref $res) {
	# do it the hard way: we cannot massage floats before doing wrapping
	$rout = mformat @$out;
	if (defined $rres and $rres !~ /\n/) {
	  $rout =~ s/\]\s*\[/; /g;
	  $rout =~ s/,\n/, \n/g; # Spaces were removed 
	  $rout =~ s/\n//g;	# Long wrapped text
	}
	if ($rout =~ /\[.*[-+,;]\s/) {
	  $rout =~ s/,*\s+/ /g;
	  $rres =~ s/,*\s+/ /g if defined $res;
	}
	if ($in =~ /\b(zeta|bin|comprealraw|frac|lseriesell|powrealraw|pollegendre|legendre|suminf)\b/) {
	  $rres = massage_floats $rres, "14f";
	  $rout = massage_floats $rout, "14f";
	} else {
	  $rres = massage_floats $rres;
	  $rout = massage_floats $rout;
	}
	$rout =~ s/\s*([-+])\s*/$1/g;
	$rres =~ s/\s*([-+])\s*/$1/g if defined $res;
      } else {
	$re_out = re_format @$out;
#	$rout = mformat @$out;
#	if (defined $rres and $rres !~ /\n/) {
#	  $rout =~ s/\]\s*\[/; /g;
#	  $rout =~ s/,\n/, \n/g; # Spaces were removed 
#	  $rout =~ s/\n//g;	# Long wrapped text
#	}
#	if ($rout =~ /\[.*[-+,;]\s/) {
#	  $rout =~ s/,*\s+/ /g;
#	  $rres =~ s/,*\s+/ /g if defined $res;
#	}
#	$rout =~ s/\s*([-+])\s*/$1/g;
#	$rres =~ s/\s*([-+])\s*/$1/g if defined $res;
      }
    }

    if ($@) {
      if ($@ =~ /^Undefined subroutine &main::(\w+)/ 
	  and $not_yet_defined{$1}) {
	print "# in='$in'\nok $c # Skipped: `$1' is known to be undefined\n";
      } else {
	print "not ok $c # in='$in', err='$@'\n";
      }
      return;
    }
    my $cmp;
    if (defined $rres and defined $re_out) {
      $cmp = eval { $rres =~ /^$re_out$/ };
      if ($@ and $@ =~ /regexp too big/) {
	print "ok $c # Skipped: $@\n";
	@seen{keys %seen_now} = values %seen_now;
	$prev = $res;
	return;
      }
    }
    if (not $noans and defined $re_out 
	     and (not defined $rres or not $cmp)) {
      $out->[0] =~ s/\n/\t/g;	# @$out usually has 1 elt
      print "not ok $c # in='$in'\n#    out='", $rres, "', type='", ref $res,
      "'\n# pari==='", join("\t", @$out), "'\n# re_out='$re_out'\n";
    } elsif (not $noans and defined $re_out) {
      print "ok $c\n";
      @seen{keys %seen_now} = values %seen_now;
      $prev = $res;
    } elsif (not $noans and (not defined $rres or $rres ne $rout)) {
      print "not ok $c # in='$in'\n#    out='", $rres, "', type='", ref $res,
      "'\n# expect='$rout'\n";
    } elsif ($doprint and $printout ne $rout) {
      print "not ok $c # in='$in'\n# printout='", $printout, 
      "'\n#   expect='$rout', type='", ref $res,"'\n";
    } else {
      print "ok $c\n";
      @seen{keys %seen_now} = values %seen_now;
      $prev = $res;
    }
  }
}

sub process_error {
  my ($in, $out, $error) = @_;
  $c++;
  print("# `$in'\nok $c # Skipping error($error) test\n");
}

sub process_definition {
  my ($name, $def) = @_;
  $c++;
  eval "PARI('$def');  import Math::Pari $name;";
  if ($@) {
    chomp $@;
    print("not ok $c # definition: `$in' error `$@'\n");
  } else {
    print("# definition $c: `$in'\nok $c\n");
  }
}

sub process_set {
  my ($in, $out) = @_;
  return process_test("setprecision($1)", 'noans', '') if $in =~ /^\\p\s*(\d+)$/;
  $c++;
  print("# `$in'\nok $c # Skipping setting test\n");
}

sub process_print {
  my ($in, @out) = @_;
  $c++;
  print("# $c: `$in'\nok $c # Skipping print\n");
}

sub process_multi {
  my ($in, $out) = @_;
  my @out = @$out;
  $c++;
  print("# `$in'\nok $c # Skipping multiline\n");
}

sub my_print {
  my $nl = shift;
  @_ = map {(ref) ? (pari_print $_) : $_} @_;
  $printout .= join '', @_;
  $printout .= "\t" if $nl;
  return;
}

sub my_pprint {
  my $nl = shift;
  @_ = map {(ref) ? (pari_pprint $_) : $_} @_;
  $printout .= join '', @_;
  $printout .= "\t" if $nl;
  return;
}

sub my_texprint {
  my $nl = shift;
  @_ = map {(ref) ? (pari_texprint $_) : $_} @_;
  $printout .= join '', @_;
  $printout .= "\t" if $nl;
  return;
}

sub prec {
  setprecision($_[0]);
  print "# Setting precision to $_[0] digits.\n";
  print "ok $c\n" unless $_[1];
}
sub sprec {
  setseriesprecision($_[0]);
  print "# Setting series precision to $_[0] digits.\n";
  print "ok $c\n";
}
