#!/usr/bin/perl


###########
# METHODS #
###########


# Imports
# -------
use Socket;
use POSIX ":sys_wait_h";



# Variables globales
# ------------------
%conf = ();
%route = ();
%exec = ();
@clients = ();

$mustStatus;
$mustStop;

$recvRequests = 0; #todo : use signals
$procRequests = 0;

$SIG{'INT'} = \&catch_stop;
$SIG{'USR2'} = \&catch_status;



# Parsing paramètres
# ------------------
sub processParams
{
	if ($ARGV[0] eq "start") { start(); }
	elsif ($ARGV[0] eq "stop") { stop(); }
	elsif ($ARGV[0] eq "status") { status(); }
	else { print "Parametre de lancement non-valide: '" . $ARGV[0] . "'\n"; exit 1; }
}



# Capture signaux
# ---------------
sub catch_stop
{
    my $signame = shift;
    $mustStop = 1;
}

sub catch_status
{
    my $signame = shift;
    $mustStatus = 1;
}






# Sauvegarde PID
# --------------
sub processPID
{
	my $a = open(PID, "<", "comanche.pid");
	
	if (! defined($a))
	{
		if ($ARGV[0] eq "start") { start(); }
		return $$;
	}
	else
	{
		my $firstline = <PID>;
		close(PID);
		
		if ($ARGV[0] eq "stop") { stop($firstLine); }
		elsif ($ARGV[0] eq "status") { status($firstLine); }
		else { (exit 1); }
	}
}



# Démarrage serveur
# -----------------
sub start
{
	my $a = open(PID, "<comanche.pid");
	
	if (! defined($a))
	{
		open(PID, ">comanche.pid");
		
		my $forkpid = fork();
		if ($forkpid != 0) # Pere
		{
			exit 0;
		}
		else # Fils
		{
			print(PID $$);
			close(PID);
			close(PID);
			! initConfig() || die "Config invalide";
			! initLog() || die "Impossible d'ouvrir le fichier de log";
			
			my $tmp = $conf{"port"};
			$tmp =~ s/\n//;
			logger("start;;$tmp;");
		}
	}
	else
	{
		print "Commande 'start' invalide, serveur déjà en cours d'exécution\n";
		exit 0;
	}
}

# Arrêt serveur
# -------------
sub stop
{
	if (! -e "comanche.pid")
	{
		print "Commande 'stop' invalide, aucune instance en cours d'exécution\n";
		exit 0;
	}
	
	open(PID, "<comanche.pid");
	my $firstLine = <PID>;
	kill ('INT', $firstLine); # -> catch_stop();
	unlink("comanche.pid");
	# check threads
	close(SERVEUR);
	
	logger("stop;;$conf{'port'};");
	close(LOG);
	
	exit;
}

# Statut serveur
# --------------
sub status
{

}



# Init config
# -----------
sub initConfig
{
	my @list = ("port","default","index","clients","logfile","basedir");
	open(CONFIG,"comanche.conf") || return 1;
	while(<CONFIG>)
	{
		my @ligne=split(/\ |\t/,$_);

		if($ligne[0] eq "set"){
		#	if(exists $list[$ligne[1]] && defined $list[$ligne[2]]){
			if(grep(/^$ligne[1]/,@list))
			{
				$conf{$ligne[1]} = $ligne[2];
			}	
		}
		
		if($ligne[0] eq "route" && $ligne[2] eq "to")
		{	
			$route{$ligne[1]} = $ligne[3];
		}
		
		if($ligne[0] eq "exec" && $ligne[2] eq "from")
		{
			$exec{$ligne[1]} = $ligne[3];
		}
	}
	close(CONFIG) || return 1;	
	return 0;
}



# Init logging
# ------------
sub initLog
{
	open(LOG,">>".$conf{"logfile"}) || return 1;
	return 0;
}



# Logging
# -------
sub logger
{
	my @args = @_;
	my $timestamp = localtime(); #todo : milliseconds
	my $all = $args[0];
	
	print (LOG "$timestamp;$all\n");
	autoflush LOG 1;
}



# Initialisation de la connexion
# ------------------------------
sub initConnection
{
	socket (SERVEUR, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
	setsockopt (SERVEUR, SOL_SOCKET, SO_REUSEADDR, 1);
	my $my_adress = sockaddr_in ($conf{"port"}, INADDR_ANY);

	bind(SERVEUR, $my_adress) || die ("bind");
	listen (SERVEUR, SOMAXCONN) || die ("listen");
}



# Attendre un processus
# ---------------------
sub waitProcess
{
	while ($currentThreads >= $conf{"clients"})
	{
		#print("Nombre max de processus atteint, patientez ...");
    	wait;
    	$currentThreads -= 1;
    }
}



# Répartiteur
# -----------
sub welcome
{
	while (accept (CLIENT, SERVEUR))
	{
		$currentThreads += 1;
		
		waitProcess();
	    
		my $forkpid = fork();
	
		if ($forkpid != 0) # Pere
		{
			$recvRequests = $recvRequests + 1;
			push(@clients, $forkpid);
			close (CLIENT);
			next;
		}
		else # Fils
		{
			my $bool = 0;
			my $firstLine = <CLIENT>;
			my $lastLine = $firstLine;

			while ($bool == 0) #todo: impl. HTTP 1.1
			{
				my $line = <CLIENT>;
				#print "ligne: $line";
				
				if ($line eq "\r\n" && $lastLine eq "\r\n")
				{
					$bool = 1;
					print(CLIENT processGET($line));
					autoflush CLIENT 1;
				}
				else
				{
					$lastLine = $line;
				}
			}

			close (CLIENT);
			exit;
		}
	}
	
	if ($mustStatus == 1)
	{
		$mustStatus == 0;
		status();
	}
	elsif ($mustStop == 1)
	{
		$mustStop == 0;
		stop();
	}
}



# CGI
# ---
sub processCGI
{

}



# Requête 'GET'
# -------------
sub processGET
{
	my $unformattedLine = $_[0];
	chomp($unformattedLine);
	my $hasMatched;
	my $requiredFile;
	my $html = "";
	my $code = 404;
	
	
	while (my($k,$v) = each(%route))
	{
		my $nbMatches = grep($cle, $line);
		
		if ($nbMatches != 0)
		{
			print "old line = ", $line, "\n";
			$line =~ s!$cle!$route{$cle}!;
			print "new line = ", $line, "\n";
			$hasMatched = 1;
			break;
		}
	}
	
	if (! defined($hasMatched))
	{
		$requiredFile = $conf{"default"};
		$html = getFileContent($requiredFile);
		$code = 404;
	}
	else
	{
		my @formattedLines = split(' ', $unformattedLine);
		my $line = $conf{"basedir"} . "/" . substr($formattedLines[1], 1);
		$line =~ s/\n//;
	
		if (-d $line) # dossier
		{
			my @files = glob($line);
		
			foreach my $file (@files)
			{
				if ($file eq $conf{"index"})
				{
					$requiredFile = $line . $conf{"index"};
					$html = getFileContent($requiredFile);
					$code = 200;
				}
			}
		
			if (! defined($requiredFile))
			{
				$html = parseHTML($line);
				$code = 200;
			}
		}
		elsif (-f $line) # fichier
		{
			$requiredFile = $line;
			$html = getFileContent($requiredFile);
			$code = 200;
		}
		else # 404
		{
			$requiredFile = $conf{"default"};
			$html = getFileContent($requiredFile);
			$code = 200;
		}
	
		$requiredFile =~ s/\n//;
	
		logger("get-s;ip;$requiredFile;$code");
		return $html;
	}
}



# Construit une requete HTTP valide
# ---------------------------------
sub getValidHTTPRequest
{
	# todo
	my $filename = $_[0];
	my $code = $_[1];
	my $contentType = $_[2];
	my $content = $_[3];
}



# Recupere tout le contenu d'un fichier
# -------------------------------------
sub getFileContent
{
	my $filename = $_[0];
	open(FILE,"<".$filename);
	my @content = <FILE>;
	close(FILE);
	
	$concat = "";
	
	foreach my $i (@content)
	{
		$concat .= $i . "\n";
	}
	
	return $concat;
}



# parser les dossiers et fichiers en html
# ---------------------------------------
sub parseHTML
{
	my(@args) = @_;
	my $folder = $args[0];
	my @fichiers = glob($folder."/*");
	my $res= "<html><ul>";

	foreach (@fichiers)
	{
		(my $f = $_) =~ s/.+\/(.+)/\1/;
		
		if( -e $_)
		{
			if(-d $_)
			{
				#dossier
				$res = $res . "<li> <a href=\"$f\">". $f . "</a> </li>" ;
			}
			else
			{
				$res = $res . "<li> $f </li>";
			}
		}
	}
	
	$res = $res . "</ul></html>";
	return $res;
}






########
# MAIN #
########

processParams();

initConnection();

$currentThreads = 0;
welcome();


