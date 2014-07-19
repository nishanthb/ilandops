/* 

Based on "multicast.c" by  Mark Claypool, 2001

Merged into a program that does both send and receive on the same application,
and to take options; Jason Fesler <jfesler@yahoo-inc.com> 2006

Usage: start on all the nodes in your cluster.  Specify the multicast
address (-a) and port (-p) to use.  Unless told otherwise, this application
will run for 30 seconds, and print out every host it sees chattering test
packets (but prints only once).




*/

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <netdb.h>
#include <string.h>

#include "./hash.h"

#define EXAMPLE_PORT 10100
#define EXAMPLE_GROUP "239.10.100.100"
#define EXAMPLE_INTERFACE "eth0"

char *progname = NULL;
extern int opterr, optind, optopt, optreset;
extern char *optarg;
int getopt (int nargc, char *const *nargv, const char *ostr);

void usage (void);
char *get_addr (int sock, char *ifname);


main (int argc, char *argv[])
{
  struct sockaddr_in addr_send;
  struct sockaddr_in addr_rcv;
  in_addr_t addr_route;
  struct hostent *he;

  int addrlen, sock, cnt;
  struct ip_mreq mreq;
  char message[4000];
  char buffer[4000];
  char blah[5] = "blah";
  struct timeval timeout;
  time_t t_start;
  time_t t_lastsend;
  time_t t_current;
  char *options = "a:p:t:T:i:v1";
  int c;
  hash_table table;
  void *p = NULL;
  int i = 0;
  int counter = 0;

  u_char ttl = 3;
  pid_t pid = 0;

  unsigned option_1 = 0;
  char *option_a = EXAMPLE_GROUP;
  unsigned option_p = EXAMPLE_PORT;
  unsigned option_t = 30;
  char *option_i = EXAMPLE_INTERFACE;
  unsigned option_v = 0;


  int gasp = 0;
  int xmits = 0;



  t_lastsend = t_start = t_current = time (NULL);
  pid = getpid ();

  p = hash_construct_table (&table, 25000);
  if (!p)
    {
      fprintf (stderr, "Failed to construct hash table\n");
      exit (1);
    }


  progname = argv[0];
  while (strchr (progname, '/'))
    {
      progname = (char *) strchr (progname, '/');
      progname++;
    }


  while ((c = getopt (argc, argv, options)) != -1)
    {

      switch ((int) c)
	{
	case 'a':
	  option_a = optarg;
	  break;
	case 'p':
	  option_p = atol (optarg);
	  break;
	case 't':
	  option_t = atol (optarg);
	  break;
	case 'T':
	  ttl = atoi (optarg);
	  break;
	case 'i':
	  option_i = optarg;
	  break;
	case 'v':
	  option_v = 1;
	  break;
	case '1':
	  option_1 = 1;
	  break;
	default:
	  fprintf (stderr, "unknown option: %c\n", c);
	  usage ();
	  return 1;
	  break;
	}
    }

  if (ttl < 3) {
     fprintf(stderr,"WARNING: TTL set low (%i); netops requires 3 or higher.\n",ttl);
  }   

  if (option_v)
    fprintf (stderr, "INFO: Address %s Port %u  Interface %s\n",
	     option_a, option_p, option_i);


  /* set up socket */
  sock = socket (AF_INET, SOCK_DGRAM, 0);
  if (sock < 0)
    {
      perror ("socket");
      exit (1);
    }
  bzero ((char *) &addr_rcv, sizeof (addr_rcv));
  addr_rcv.sin_family = AF_INET;
  addr_rcv.sin_addr.s_addr = htonl (INADDR_ANY);
  addr_rcv.sin_port = htons (option_p);
  addrlen = sizeof (addr_rcv);

  bzero ((char *) &addr_send, sizeof (addr_send));
  addr_send.sin_family = AF_INET;
  addr_send.sin_addr.s_addr = htonl (INADDR_ANY);
  addr_send.sin_port = htons (option_p);
  addrlen = sizeof (addr_send);



  addr_send.sin_addr.s_addr = inet_addr (option_a);


  /* receiver plays out messages */
  if (bind (sock, (struct sockaddr *) &addr_rcv, sizeof (addr_rcv)) < 0)
    {
      perror ("bind");
      exit (1);
    }


  p = get_addr (sock, option_i);
  if (option_v)
    printf ("INFO: My address is %s\n", p);

  addr_route = inet_addr (p);
  if (setsockopt (sock, IPPROTO_IP, IP_MULTICAST_IF, (void *) &addr_route,
		  sizeof (&addr_route)) < 0)
    {
      perror ("setsockopt ip_multicast_if");
      exit (1);
    }

  mreq.imr_multiaddr.s_addr = inet_addr (option_a);
  mreq.imr_interface.s_addr = htonl (INADDR_ANY);
  mreq.imr_interface.s_addr = inet_addr (get_addr (sock, option_i));

  if (setsockopt (sock, IPPROTO_IP, IP_ADD_MEMBERSHIP,
		  &mreq, sizeof (mreq)) < 0)
    {
      perror ("setsockopt mreq IP_ADD_MEMBERSHIP");
      exit (1);
    }


  if (setsockopt (sock, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof (ttl)) < 0)
    {
      perror ("setsockopt ip_multicast_ttl");
    }


  if (fcntl (sock, F_SETFL, O_NONBLOCK) == -1)
    {
      perror ("fcntl F_SETFL O_NONBLOCK");
      exit (1);
    }

  while (1)
    {
      gasp = 0;
      while (1)
	{
	  message[0] = 0;
	  cnt = recvfrom (sock, message, sizeof (message), 0,
			  (struct sockaddr *) &addr_rcv, &addrlen);
	  if (strcmp (message, "TEST") == 0)
	    {
	      strcpy (buffer, inet_ntoa (addr_rcv.sin_addr));
	      he = gethostbyaddr (&addr_rcv.sin_addr.s_addr,
				  sizeof (addr_rcv.sin_addr.s_addr), AF_INET);
	      if (he)
		{
		  if (he->h_name)
		    {
		      strncpy (buffer, he->h_name, sizeof (buffer) - 1);
		    }
		}
	      p = hash_lookup (buffer, &table);
	      if (option_1) printf ("%s\n", buffer);
	      
	      if (!p)
		{
		  if (!option_1) printf ("%s\n", buffer);
		  p = hash_insert (buffer, blah, &table);
		  counter++;
		}
	    };

	  if (cnt < 0)
	    break;

	  // Make sure that we occasionally double check the time
	  if ((((++gasp) % 100) == 0) && (time (NULL) != t_lastsend))
	    break;

	}

      t_current = time (NULL);
      if ((t_current - t_start) > option_t)
	{
	  if (option_v)
	    printf ("INFO: %lu count found; I did %lu xmits\n", counter,
		    xmits);
	  exit (0);
	}
      if (t_current - t_lastsend > 0)
	{
	  t_lastsend = t_current;
	  if ((((t_current + pid) % 2) == 0) || (option_1))
	    {
	      memset (&message, sizeof (message), 0);
	      sprintf (message, "TEST");
	      cnt = sendto (sock, message, strlen (message) + 1, 0,
			    (struct sockaddr *) &addr_send, addrlen);
	      xmits++;
	      if (cnt < 0)
		{
		  perror ("sendto");
		}
	    }
	}
      else
	{
	  timeout.tv_sec = 0;
	  timeout.tv_usec = (option_1) ? 1000000 : 100000;
	  
	  select (1, NULL, NULL, NULL, &timeout);
	}
    }
}


void
usage (void)
{
  if (!progname)
    {
      progname = "a.out";
    }
  fprintf (stderr, "Usage: %s [options]\n", progname);
  fprintf (stderr, "-a ADDRESS   - use this multicast address\n");
  fprintf (stderr, "-p PORT      - use this port\n");
  fprintf (stderr, "-i INTERFACE - ie, eth0 or eth1\n");
  fprintf (stderr, "-t TIME      - time in seconds to wait\n");
  fprintf (stderr, "-v           - Verbose messages\n");
  fprintf (stderr, "-T TTL       - default is 3, minimum is 3\n");
  fprintf (stderr, "-1           - Chime every second, report every chime\n");
  fprintf (stderr,
	   "More info: http://twiki.corp.yahoo.com/view/YSTProdEng/HowToTestMulticast\n");
}


char *
get_addr (int sock, char *ifname)
{

  struct ifreq *ifr;
  struct ifreq ifrr;
  struct sockaddr_in sa;
  char *p;

  memset (&ifrr, sizeof (ifrr), 0);

  ifr = &ifrr;
  ifrr.ifr_addr.sa_family = AF_INET;
  strncpy (ifrr.ifr_name, ifname, sizeof (ifrr.ifr_name));

  if (ioctl (sock, SIOCGIFADDR, ifr) < 0)
    {
      fprintf (stderr, "get_addr: No %s interface.\n", ifname);
      exit (1);
    }
  memcpy (&sa, &ifrr.ifr_ifru.ifru_addr, sizeof (ifrr.ifr_ifru.ifru_addr));
  p = inet_ntoa (sa.sin_addr);
  return (p);
}
