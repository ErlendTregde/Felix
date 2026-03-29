Transkripsjon


Søk i videoen
0:00
good everyone today we're going to do the much anticipated proximity chat
0:05
tutorial so before we get started uh we're just going to have to refer to two quick figures here so the
0:13
first one proximity chat equals more fun I can't really deny that that's just the
0:19
truth and so figure two for anybody that doesn't understand what proximity chat is we got player one here hanging out by
0:26
himself just doing whatever and then player two comes along and then
0:32
potentially tells player one to go and play another game right so let's get started so first we want to go to GD
0:39
steam.com um because you can't I mean you can sort of install a plugin for gdau that does uh the steam stuff but
0:46
you're better off just downloading What's called the pre-compile so just go to gdos steam.com then up the top right
0:52
we want to click on the GitHub link um and don't turn away just yet right down
0:58
here we want to find the pre-compile for multiplayer peer so if you click on that it'll take you to another page and
1:06
then on the right here we can click on releases and so here you're going to see a whole bunch of stuff but it's
1:11
basically just the gdau version 43 uh s161 is the Steamworks version so
1:17
you can check out the steam SDK and make sure that this is the version that you want I think this is generally not the
1:24
most up toate version but it's up toate enough um this plug-in what do you call
1:30
it the pre- compiles they update often enough uh Steamworks 161 is just fine
1:35
and then you've got GTO steam 4.12 which is obviously just the goodto steam version so down here as well we've
1:42
got win 64 which is the 64-bit version uh for most users you're going to want to click on this uh you also want to
1:49
download the multiplayer templates um but there's a lot of videos that'll go into detail about how to do that um
1:56
pretty much skip two once you're ready open yourself a new project and then we
2:01
can get really started so the good thing about the pre-compile as opposed to the
2:07
asset lib steam uh which I'll just look up right now to show you so make sure it's by Gramps this is the man uh gdau
2:16
steam extension this is generally the one that you would install so the difference between that and the version that we're running right now is that if
2:23
we just create our steam uh what do you call it Auto
2:29
autoload just going to create this
2:34
here we're going to call it steam manager and you might have just seen that red text show up just then I'll
2:39
show you what that was talking about create a folder called scripts open
2:45
we're going to create to make sure it's on uh and then open it up just by clicking on it there so the big
2:51
difference between this pre-compile is we've already got steam imported as a
2:57
module so just like the the what do you call it the plug-in would do except
3:04
we've got extra functionality in here with uh what do you call it the steam
3:11
multiplayer here which this is really the reason that we went to that steam
3:16
multiplayer perer pre-compile back here because this is this is what we
3:23
want okay so that being said so we're going to need to do a few steam things
3:29
here really quickly so the first thing we want to do is
3:35
RA Steam app ID and equals 480 so this is space War
3:41
this is like the the test uh app ID we're going to get the Steam
3:49
username C nothing at the moment and then get the steam
3:56
ID cool so then a couple little Lobby things we're going to add in
4:04
here so these are just for the lobby things Lobby ID I think we
4:10
need yeah we don't want space Lobby members I don't really think we need
4:18
that but we're just going to stick that in there anyway so in uh ready actually I think we need
4:25
an init function here yeah and then there we're going to
4:31
set the uh what is it Steam app
4:38
ID string Steam app ID and
4:48
then steam game ID let Control Alt down as well to duplicate
4:56
lines and in the ready function we need to get our callbacks actually we going to
5:03
initialize steam first then in process we got one here we
5:08
need to steam do run callbacks I
5:15
believe cool now that we've done that steam
5:22
should be initializing and loading in sweet I guess next step is actually
5:30
get those details so steam ID equals steam. getet steam
5:40
ID uh and then we'll print the steam ID we may as well just to make sure it's
5:45
working uh maybe I shouldn't print mine while we test this Steam
5:53
username steam. getet Persona name so we get their name on Steam we
6:01
might as well print that
6:07
beautiful um we can set up our signals later we just need to get all of this set up
6:13
so that's our autoload we actually need to have a main scene and then we need to have uh players so we should probably
6:20
work on that now so I'm just going to set up a quick scene I'll call this main
6:27
scene save it as scenes course main scene and we'll add
6:34
the script to it early may as well put it in scripts main scene cool so we got something else to
6:41
work with and what should we do okay so we'll
6:46
go CSG box I find these work a lot better as floors generally than
6:54
a just a quad wood because sometimes you fall
6:59
through the ground it's really stupid so I'm not going to put um what do you call
7:05
it jolton or anything crazy like that we're just going to make a big
7:10
box we're going to use collisions uh Collision layer one yep so we'll call
7:16
that world get into the habit of doing this as well it's really good habit to
7:22
be doing I think player players maybe on two um and then maybe like rigid bodies
7:33
um I guess we're not even really going to use that I just like to be prepared you know in advance so as well the
7:41
visual instance here we're going to go world and then we're probably going to put the players on two I like to just
7:47
split them up just in case I start using decals or something to keep it away from the world so now that we've got that we may
7:54
as well import some textures textures
8:00
cool so I like this concrete texture just going to quickly do a tri
8:07
planer on it probably should use like a sample UV
8:12
texture but I don't want to I like this one this one shows the ground which is
8:20
all I want to turn the specula down generally um we're also probably going
8:25
to need an environment so we'll do it the easy way bang and bang right click reparent
8:31
to new nodes we just choose a regular node cuz uh the position doesn't matter for these
8:38
nodes they're just environment maybe we'll make it look a little bit
8:45
nicer I just don't like that brown ground it's just so
8:51
ugly just something a little bit nicer like
8:57
a you're going then the Horizon would do some
9:02
like crazy blue in the sky let's get like something
9:08
nuts in there yeah there we go
9:14
beautiful fantastic it'll do for now looks like the toxic gas from uh that Spider-Man
9:21
game for the PS1 between the buildings so we're going to just make
9:28
this a little bit bigger about half cool so that's the world for
9:34
now we're also probably going to need to create a uh node for where the players spawn
9:42
in so node I always do that I start typing
9:48
when I go to type the the node name in we call that players and then we're
9:55
going to create a multiplayer spawner we're going to call that uh
10:01
player spawner cool we're going to need to attach a script to that but we'll figure
10:07
that out we also need to create our players so we're not going to mess around too much with
10:13
that too much with that just yet yeah cuz I mean we're going to need
10:18
a spawn an element yeah H spawn path well we'll just go to
10:25
players for now mul player spawner here so we need
10:31
to add a script to that but we're going to do
10:37
that yeah we'll do that now may as well so we'll create the script player
10:43
spawner and scripts all right let's just type this
10:49
out export Vibe player scene and this is where we're going to actually add the player scene
10:56
in so we'll work on that next right after we do the world um and I think
11:01
that's all we're really going to need it's just the world the players uh and then steam spawning stuff
11:08
in naturally with steam multiplayer here so spawn function equals spawn
11:15
player we're going to need to add that down here
11:21
uh I guess daughter uh we'll pass that for now
11:29
function so this is like inheriting the the multiplayer spawner uh class or node
11:36
whatever you want to call it I'm still kind of new to uh gdau um I've been using it for the last
11:43
like maybe year and a half almost um but by far the best um the
11:52
best thing about uh Gau is the way it connects with steam it's just so easy so spawn we're also going to need
11:59
need that um it's going to link into itself so
12:04
it's going to run its own spawn uh function uh which is where is it ah it's
12:13
around here somewhere that's the other great thing about gdos having the ID in and being able to just go to the
12:18
documentation it's just so great um then we probably going to need here
12:26
disconnected I'm going to need to create a function for that we call it remove
12:32
player uh and then spawn the host
12:38
right l so we want to call defer this as
12:44
well spawn host so we'll start with that
12:49
actually if is multiplayer
12:57
Authority come on oh it's say his that's
13:04
why multiplayer Authority uh spawn one that's
13:10
us uh so spawn host defer me
13:19
right yeah cuz we need to we need to defer that cool so remove player as well
13:24
there another one that we need as well as spawn player so
13:31
just Chuck this up here for the meantime it's alt and up to move stuff
13:37
around by the way you just choose the lines a lot of cool little little keyboard things Oh Long
13:46
spawn player uh remove player data I suppose then we go
13:54
players data. Q
14:01
uh fre I think players da Q3 and then players
14:07
arrays data cuz that's going to be the player in there spawn player
14:14
so equals player scene do
14:20
instantiate e do set multiplayer Authority data not the two brackets
14:30
players data dot no equals p and I return
14:40
P players call spawn so we've got a ready
14:47
spawn poost spawn player remove player I think
14:52
that's actually going to be it for this so we'll just leave that one
14:57
there go back to the main scene uh and then we need to create our player so
15:03
it's probably going to be a character body 3D cool so this is where it starts
15:10
to get interesting call this player some stop starting as well just to save you a
15:16
little bit of time while I get reference on this stuff we want to save a branch as scene
15:24
as the player into scenes call it player and then we want to open that cool so
15:31
everything's all zeroed out perfect then we want to add a
15:39
script scripts add script player oh and it's given us this oh that
15:45
that's cool for now yeah just so we can move around and stuff I we should see what that looks like actually h no shape
15:53
so we're going to need to add a collision shape to it just make sure it's like a bean or
16:00
something I'm going to need to add 0.25 I usually do and
16:06
1.8 move this up by 0.9 that's usually where I've got my
16:14
stuff and then I'll add a camera up to
16:20
1.5 is area I like to usually have it and then I'll just push it forward a little
16:27
bit sometimes it's a little bit janky having it right on the circle well
16:33
usually I'd add in a neck as well but screw it we'll just keep it there that will
16:39
do now on that script we're going to need to we've got to figure out where the
16:45
camera is
16:51
um probably get export the player
16:57
name String calls uh new player or call
17:04
him I don't know um Larry I do hopefully
17:11
we don't see Larry but we might I'm going to want the steam
17:17
ID uh yeah steam ID zero for
17:24
now um maybe we put a player label on top of him as well so
17:30
label 3D and this will just say Larry on
17:36
it for now oh yeah we might need to change the direction that the camera goes just you
17:43
know how it works with the Zed and moving forward and which way it prefers forward
17:49
to be because it might even be going back that way uh so the camera might be in the wrong direction but we'll we'll
17:56
find out course so we've got larryan here uh and I make sure that it's
18:02
lowercase there and then uppercase here just so I can tell if it's being set
18:07
through the code or if it's uh a default and not being set at all cool so those couple of things
18:15
awesome cool so I'm thinking I should be able to run this and
18:21
check uh select current no no no no no no no control alt shift s to save all
18:29
scenes hit play here select current let's see what we
18:34
get oh of course yeah so this is going to break right now because
18:40
um the player spawner we don't want that in just yet how about
18:47
that okay so forward yep okay forward's working awesome so this is going to be
18:53
our players I guess maybe we should add a key for turning because I really don't want
19:00
to have it linked up to my mouse right now but anyway uh that'll do for now I
19:07
suppose it'll give us the the spatial awareness that we need for proximity chat to work and we we fall off the end
19:15
cool awesome now we can put that script back on we're
19:21
going to delete player now we're going to just add player directly to our
19:30
multiplayer spawner so the scene which is awesome we might also add a spawn
19:36
position so a marker 3D just have it like here so we'll call
19:45
that spawn position we're probably going to want that in the main scene as
19:52
well yeah probably cool now as you'll see because of that player spawner
19:57
having the player scene in there if we then go play the game we spawn in even
20:03
though yeah it wasn't the player isn't actually anywhere in there is awesome so
20:09
if we move that player spawner we can't move the player spawner so it's just spawning at position 0000 and that's why
20:15
we've got the spawn position thing here but I think that's probably only going to work for the peers for now but we'll figure it out later it's just good to
20:22
have that reference early cool so another thing we have to do is back in
20:27
our steam manager want to create up here
20:34
here so I like to do it this way because um I I ran into a crash when I don't do
20:41
it this way so we initialize our steam well we we have like a reference
20:48
to the steam multiplayer here basically so basically we just keep one for now at least that that's
20:55
the way that we're going to um that's the way that we're going to test
21:01
it for right now we might have to come back to that cool so now that that's
21:06
done um we basically need to set up a Lobby uh and then connect another player into that Lobby and then that should
21:13
spawn in another player so I suppose first of all we we've got
21:18
to actually get um I mean it's just going to be a flying around name uh for right now so we're going to have to add
21:25
in some sort of mesh in 3D uh so we're going to go capture uh
21:33
0.25 1.8 and then lift it up by 0 9 cool just so it's in the same area
21:41
and now this should be able to still see through that um just because of the material not having back faces on by
21:49
default sweet as so that should do make it a little bit more janky just for
21:56
funsies little bit like that why not not like it
22:02
matters two all right there we go it's basically like a no no no we'll go
22:07
through five here and the two there yeah right
22:13
perfect so actually we've also got to add
22:18
our audio stream player 3D and we are going to call that one um
22:27
what should we call it proc Network and proc local
22:34
probably so we're going to have a loop back just for
22:39
ourself and um that's basically part of the tutorial that you learn here for uh
22:45
voice in gdau this is where I'm getting all of my uh information from as well as
22:51
uh two tutorials by gwiz that talk about um networking PE peer-to-peer functions
22:57
cool and I believe those need to be audio stream
23:03
generators both of them so now we can either look at the player script here
23:10
for the voice chat or we can do the lobby stuff and I think we should probably do the lobby stuff first just
23:16
for ease and our continuity I guess so we're going to create a button on the
23:23
interface uh in the main scene so we'll add our control
23:29
uh we'll call this the um the multiplayer UI so what do we need
23:35
to have we've got to have a we'll just do a hbox container for now
23:41
then we'll add some buttons in so we'll have one for host call this one host button have
23:50
another one for join um
23:59
that should do for now so that join button is actually going to be uh like a lobbies button so when you
24:07
click on it it should load up some lobbies so then we've got to have a vbox and put this inside of
24:15
that um what do we have in there it's a scroll
24:21
container with a list of lobbies inside of that so
24:27
we're going to add a v-box container as well
24:33
and make that full size so this entire area we'll just make sure
24:38
that it's big enough so 500 by 300 that'll do uh and we make
24:48
this overlay not mess with the mouse in game but not that it's really going to matter that much um but you could go
24:55
Mouse ignore um and then also we could
25:00
do this expansion stuff where is it this layout container sizing
25:08
expand I guess it really doesn't matter so then here I guess if we start adding
25:16
buttons cuz this is what it's going to look like blah blah blah server blah blah
25:22
blah server yep so we've got to expand this so this is going to say
25:29
Hello's server and then we'll have one out of two people so it'll look
25:35
something like that we just going to have a little list pop up there so we need the scroll container so we can scroll
25:40
through the entire list of lobbies so we call this one lobbies list
25:46
um this one lobbies scroll container uh we can leave these buttons
25:53
in here six out nine
26:01
yeah 4 out of 20 so we can leave these in here for now because every time you hit that join button it's going to
26:07
refresh this list anyway um we're going to see a whole bunch of servers pop up anyway because we're using um app ID
26:14
number 480 which is space War so I didn't realize this is an actual real
26:20
game damn maybe I should play Space War sometime cool so now that we're in here
26:26
we're going to uh here
26:33
equals steam multiplayer here and then we're going to
26:39
go here equals steam manager dop just to make sure that we're all
26:47
sused out because the piers shouldn't change I've had issues yet opening and closing peers if we just have one pier
26:52
and we can connect and disconnect uh the whole thing runs a lot smoother um
26:57
instead instead of getting hung up like not quitting from lobbies and stuff like that so we're going to add
27:05
some signals in here going to attach some signals I should say some functions
27:11
for host button join uh we're going to need a reference to the lobbies
27:20
list yeah so on join buttons so first of all we're going to go VAR lobbies
27:27
buttons equals uh lobis list.get
27:33
children and then we go for I
27:38
lobbies button buttons I do Q3 so that just gets rid of
27:46
those um buttons those test buttons but also it'll refresh essentially every
27:52
time we hit join uh the lobbies so the host button it should be quite easy easy
27:58
because we're setting the pier we're going to go well we've got uh Lobby ID
28:03
as well is one that we're going to so V Lobby ID
28:10
equals uh1 just go
28:18
zero uh Lobby
28:23
created bull equals false so if not Lobby created or if
28:30
Lobby created I should say uh we return return I got a really bad habit
28:37
of leaving my cursor over where I'm typing as well if Lobby created
28:43
return else we don't need to do else do we cuz we've got the return so
28:51
Pi dot create
28:59
Lobby steam multiplayer here dot this is the lobby
29:04
type Lobby typ public then we go multiplayer
29:13
here equals Pier awesome so that's going to create
29:19
us a Lobby and now we need to find those uh we've got to find the lobbies
29:26
so the next thing we have have to do is open up a Lobby list but first of all we
29:34
have to Pi do Lobby created so we've got to actually set the
29:40
details of the lobby connect so on
29:47
Lobby created and I'm going to need to create that function on Lobby created so what do we
29:56
get in that I think we get um it's like a Lobby ID so it's a
30:03
connect Lobby created it's this here connect and Lobby int course slap that
30:12
there one lobby created so if connect
30:18
um Lobby ID equals well this Lobby ID so it's this
30:26
one we're going to need to do that Lobby ID and then we go steam do
30:34
set Lobby data Lobby
30:41
ID uh name yeah name I think it
30:47
is yeah it is yep steam. getet soner
30:53
name or I suppose we could do steam manager
30:59
do Steam username
31:04
uh plus Lobby there we go just using the
31:13
freaking inverted commas set Lobby data and we need to set the lobby as
31:21
joinable yep so Lobby ID and
31:26
true and then we go steam manager. Lobby
31:32
ID equals Lobby ID and we do have that in here don't
31:39
we we do have a Lobby ID cool we've got his Lobby host as well so should
31:45
probably set that as well is Lobby host equals
31:55
true not sure if we're going to use that later but add it in there for now anyway
32:00
cool so we've created the lobby and now the lobby is ours
32:06
um we're already spawned in yeah we're already spawned
32:14
in we need to have an unjoined as well
32:19
so here do no it won't it'll be like
32:26
a hm so I guess we should just start with the uh Lobby button so that's going
32:32
to be on join so right down about here we can get to start writing some
32:39
code so here we want to uh open Lobby list so basically we're going
32:48
to find out what lobbies are actually open so we just stick this in
32:56
here open Lobby list let go steam.
33:03
add request Lobby list distance filter yep so we're just going to set that to
33:13
worldwide so it's everyone um that's a good way to do matchmaking as well uh you find a server
33:20
that's close if you can't you find another server you check how many people are in the server and if there's space
33:25
for you it's a really easy way to do matchmaking request Lobby list so this
33:32
is what we want if we spell it right and then we're going to wait for a call back from
33:38
Steam which is I think it's uh steam Lobby match list yeah that's it so back
33:44
here we're going to go steam. Lobby match list.
33:50
connect uh on uh Lobby
33:56
match list so once we get back a list of lobbies that's what that
34:03
is down here on Match Lobby list we need to
34:09
figure out what we get back from that so it's just lobbies as array Lobby match
34:15
list yeah lobbies as an array
34:20
cool awesome so on Match Lobby list here's where it gets fun I think
34:27
it's called Lobby L list yeah lobbies list so that's our our list of lobbies right here so now we need to populate
34:34
that with like little buttons that we can press that'll join a function called join Lobby and then I
34:41
guess what was that join Lobby and then we'll have
34:46
the lobby ID in here I think that's how it works
34:53
anyway on Match lus so we iterate the lobbies for Lobby
34:59
in lobbies [Music]
35:04
um Lobby name equals steam. getet Lobby data Lobby and
35:15
name member count and max players I guess that's what we want get num Lobby
35:24
members get Lobby member limit
35:30
Lobby members and this one will be get Lobby
35:37
member uh limit yeah so we figure out how many people are in the
35:42
server and how many people are allowed to be in the server so the member count and then
35:49
we've got max players cool and I'm going to create a little button so
35:56
vbot button. new and this little button is going to created for every
36:04
single uh Lobby of finds so we Zoom this in a little bit more but. text or set
36:11
text sorry um what are we going to do we're going to
36:17
do not with the curlies first we going to do that do the cures on zero and
36:24
[Music] then one SL2 right
36:32
format uh we make an array Lobby
36:37
name member account and max players cool so that
36:44
should just create a nice little representation of it so then but do set
36:52
size we'll just give it a a minimum size I don't think this is
36:58
really going to matter but we'll give it a minimum size of 600 by 100 uh maybe 500 by 100 I think we've
37:06
only got we'll make it 400 by 50 how's that so but.
37:15
pressed.
37:21
connect join Lobby and then we're going to bind the information to this
37:29
name the lobby and then Lobby finally lobbies list
37:39
addchild uh but there we go so we should get a button for every single Lobby that shows
37:45
up uh and that might actually work now let's give it a go so if we go join we're going to see
37:53
all of these different lobbies and so these are the space War lobbies these are other people testing uh space War so
38:01
we don't need to use that for now but that's going to be good um for debugging very soon so we can already walk around
38:07
as you can see the players already spawned in um but because we've got uh steam signals connected to our spawn uh
38:15
players spawn we should see yep we should see players spawning in uh we're going to do
38:22
a little bit of work to change the name from Larry to their actual steam name but it's going to involve like a little
38:28
bit of a handshake and stuff like that but we'll get around to it let's let's continue going so join Lobby is where
38:36
we're up to now join Lobby is quite easy we've just got to go Pier dot connect
38:43
Lobby and then we put in the lobby ID that we've got
38:49
here um but we've also got to set the multiplayer here in
38:56
gdau ALS Pi here and then Lobby ID cuz we've done this for the
39:04
server equals Lobby ID yep and I guess at some point we do
39:12
need to hide that menu so we'll create a little function called hide
39:20
menu and that's just going to be the multiplayer UI I'm just going to hide that
39:28
do hide cool so hide that for now we'll put
39:33
that there and then also once we've created the lobby on Lobby created we're going to
39:40
hide the menu as well so let's just see what happens when we do that we're going
39:45
to host and Bam so now that that's gone away it means that we've gotten the
39:51
signal back from Steam saying that the lobby has been created uh which is great
39:57
great um so if we were to load up another instance which
40:03
we I don't ever do this because it seems to never
40:09
work uh because of steam but let's say if we host here and then we join here
40:15
look our our lobby is actually here so let's see what happens if we try and
40:21
join I uh don't think it's going to join because we're on the same steam ID um
40:27
and there should be an issue some here somewhere look you cannot add a peer that is you so somewhere on the steam
40:34
Network they're figuring out that I've got two computers connected to the same uh steam ID trying to connect into the
40:41
same Lobby and it's saying no and that's like a hard uh stop on their end
40:47
so if you don't want this to happen you have to have another computer which
40:53
thankfully I do where we can send this over to it to get things working so I'm
40:59
just going to have another little once over my code uh before I export it and then we'll see how it goes on two
41:06
computers course so screw it we're just going to try it see what happens and here you want to add in your
41:15
uh templates so I'm just going to add them in here in uh
41:20
release and debug I suppose so I've got mine here I think I chose debug just
41:26
then so I'm going to find inside the templates the debug one I'm going to
41:31
open that and then in release I'm going to do the one without the word debug in
41:38
it okay come on I think actually we're having that graphical it glitch that happens
41:47
sometimes see it in the background yep so I debug and then we want our
41:53
release it's just taking me to the wrong folder that's all so that that's going to be this one now that we've got both
41:59
of those in there this should export fine proc chat here I'm going to do
42:06
builds and then I'm going to add another one prox chat and then in here prox chat pro.exe
42:14
yeah screw it that'll do and then we'll wait for it to work sport cool we'll see
42:19
if that worked
42:44
on on so another thing is we need to have this steam API 64 next to or it's
42:49
not going to work all right beautiful so I've just tested that Bam um join yeah
42:57
Okay so we've got steam connection through the exe that's pretty important if if you're not getting that join working now debug right now because it's
43:05
yeah it's a it's a big deal from this point on and generally it's just because of that steam uh API 64 DL cool so let's
43:13
see if this is going to work multiplayer I've just got it set up on another computer real quick let's see how we go
43:20
so I'm going to host take a step back and on this one I'm going to join
43:29
and we're in but we can't see anything interesting
43:37
okay okay I think we need to make a couple changes to our player the first thing is if not multiplayer
43:48
Authority then we just return here so that's just to ensure that it doesn't
43:54
mess around with anything so we don't have any input here uh function ready we're probably
44:02
going to need to add a ready function here Funk ready
44:08
um yeah there's going to need to be a lot of things in here but the first thing we'll do is add to
44:15
group uh players yeah add to group players that'll
44:21
do y we just need to make sure that the players are spawning in before we can do the proximity chat stuff makes sense
44:28
right cool and then we'll go if is multiplayer
44:35
Authority uh then we can go I suppose we get the camera 3D and we can set that as
44:42
current Set current I think that's how you do it yep Set current oh Set current true
44:50
interesting it's a strange way to do it okay Set current true uh what else do we
44:56
need to do is we're going to go player name equals steam.
45:02
getet Persona name or we can go our steam manager
45:08
dot Steam username yeah then the steam ID equals
45:15
steam manager. steam ID then we go
45:22
else steam ID equals multiplayer multiplayer
45:29
peer doget steam64 from here
45:38
ID get multiplayer
45:44
Authority y cool and then player name equals steam dot get friend
45:57
Persona name steam ID so this will work for now I mean in the future you probably should
46:03
just send your your name over but this will work for now just for
46:08
friends player name label oh what do we call
46:16
that yeah we want to call it the player name label it's good we didn't bring it in
46:23
yet player name label set just go text
46:30
equals uh player name then we can
46:35
go I think that's it really for our player for right
46:40
now um and we'll see how that goes cool so I think it's spawning in now what
46:47
we're going to do is change that camera to not be current now that we've got it going through code it's probably going
46:53
to cause issues in the future and we've also got to add another amazing node that we get to
47:02
use uh without any plugins or whatever with
47:08
the steam multiplayer which is the multiplayer synchronizer so this saves you so much
47:14
work in rpcs what we're going to do is get the
47:19
player we're going to synchronize the player's
47:25
position we're going to I synchronize any of this yeah probably not the
47:32
position even though we don't have any rotation yet we're just going to get on
47:37
top of it now and do we have what sort of
47:43
velocity I guess it doesn't matter this will do for now so just position and rotation we're going to keep it on
47:48
always for now um generally you should put it on on change um but that's a case
47:54
by case basis so we're going to see what that looks like I'm just going to export that again and I'm going to get this
48:00
running on my other computer real quick see what it looks like all right fantastic so I was able to load in got
48:06
the other players's name showing up uh backwards but it doesn't matter so we're
48:11
both moving around I am just going to check that I can see him on my
48:16
screen and it looks like I can't but it doesn't really matter right now um this
48:21
is start that's really cool very good cool so to get the host to actually
48:28
spawn in at the right time we've got to wait until the server is created before
48:34
we spawn the host so I'm going to go to the main scene and pull in the player spawner
48:39
hold down control bring it in as a
48:47
variable and now we're going to go to on Lobby
48:54
created and then go player spawner do spawn
49:00
host cool and so once the game's actually been created then we spawn the host in and then it should sync with the
49:08
client so we're just going to test that real quick cool so let's just test this I'm going to host
49:14
here I'm going to join on my
49:21
laptop then we should see him spawn in and move around
49:28
and then on my laptop can then see the host moving around
49:36
too cool Okay it definitely works I wasn't sure for a second there we're definitely getting synchronization on
49:41
both sides awesome cool so the video has been quite
49:46
long so far setting this up but it's because we need all of these things to be working which is the world uh the
49:53
players uh lobbies is set up um the sync nodes are now working and so now we've
49:59
got to focus on the P2P and the proc chart which go hand in hand so back in the steam manager we're
50:05
actually going to add quite a lot of code uh it's mainly to facilitate for
50:11
the peer-to-peer stuff um and then through that we can work in handling um the proximity chat
50:17
data through the peer-to-peer uh calls so here we go we're going to
50:23
add b or actually it's constant
50:29
packet uh read limit we integer
50:37
32 um and then we need to add in some signals so we've got steam. Lobby
50:46
joined do connect uh on Lobby join We'll add that
50:53
soon and then we've got to add steam. P2P
50:58
session request uh do connect it'll be on
51:05
P2P session request again gws has a really good tutorial on peer-to-peer
51:11
stuff for uh steam so if you want a little bit more detail go check that out
51:17
now we're going to create our bunk
51:22
on on Lobby joined
51:27
so that's this Lobby
51:35
ID missions we get
51:40
locked uh
51:46
response let me go if
51:54
response chat turn
52:00
response success then Lobby
52:05
ID equals this Lobby ID and then we're going to add in a
52:12
couple more little functions here but
52:18
first going to do this on P2P session
52:25
request go bunk PDP session request and then it's
52:30
just the remote
52:38
ID and then we just want to go steam. accept
52:45
P2P session with user remote
52:52
ID cool go back to this on Lobby joined and then we want to do
52:59
get Lobby members and make P2P
53:07
handshake so then we'll make those two functions we got bunk make p top
53:20
handshake which would just be send P2P packet which we need to create another
53:26
one inspect we'll just do that one
53:33
first get rid of Lobby members PP
53:38
handshake just put pass here for
53:45
now uh Funk and P2P
53:54
packet this target
54:01
uh where my fingers send Type n equal Z for
54:11
now and then we want to go
54:16
V Channel this data is a packed B array
54:27
this data. pen array R to
54:38
byes packet data and if this
54:45
target was Zero if Lobby members do
54:52
size greater than one me
54:58
Lobby members if member steam
55:05
ID one equals to steam
55:11
ID let a little bit space
55:17
here steam. send P2P packet
55:27
steam ID this stter send
55:35
type and channel cool so then we be
55:41
like L if this target equals one which is going to be the
55:49
other our packet type which is actually our voice if this target equals steam so
55:55
probably just going
56:01
to I mean this should be the same but we're just going to do this for now just brute force it um because I think I had
56:08
some issues with this before and if we're not going
56:13
to scroll around s PP packet let
56:22
Target this data send
56:27
type and channel cool so that's our send pay top
56:33
packet function like I said you go check out gwiz if you want a little bit more information on
56:39
it I think this was in the second multiplayer tutorial one of the more recent ones
56:45
actually so then we're going to do the get Lobby members write that one down here fun get
56:52
Lobby members and that's just just going to be clearing first of all the lobby
57:06
members n of Lobby
57:12
members get the amount steam dot get num Lobby members yeah and then
57:21
we put the lobby ID in and then now that we've got the
57:27
number member in range 0 to L
57:35
members we just had a big cat Rock up to my house yeah thanks Electa I can hear
57:43
that steam. getet Lobby member by index Lobby it and then
57:52
member member
57:57
I remember steam name String equals steam. getet
58:05
friend Persona name like I said this will work for now um but you're probably going to want
58:11
to not rely on this in the future especially for people that aren't
58:17
your friends start pend like I said it'll work for
58:23
now steam ID remember there a damn big
58:31
cat steam name going to one as
58:37
well steam name cool and then we want to make the
58:45
peerto peer handshake make P2P handshake one's going
58:51
to be easy it's just send peer to-peer packet
58:57
I want zero and then
59:03
message the word handshake handshake
59:10
yep steam ID and then the steam
59:17
ID and then we want username and that will be the Steam
59:24
username just like that that should be good yep
59:31
just like that and while we're at it we may as well add our voice peer-to-peer
59:36
function here so we'll just call it
59:42
send voice data so we go voice data it
59:49
packed packed by aray y I think that should do yep and then we do the same
59:56
thing as we do here remember is alt control down to copy change that to one change this to
1:00:04
voice data make that voice data there as the
1:00:10
input and then we can keep the rest of it the same
1:00:15
awesome then we need to read the peer to-peer messages so we want to go up to
1:00:23
process and then before the steam call backs we want to do if Lobby ID is greater than
1:00:32
zero then read all P2P
1:00:37
message packets and then we're also going to read all
1:00:43
PTP voice packets yeah voice packets cool so then we've got to make these two
1:00:49
functions we're going to start with read all peer-to-peer message packets
1:00:56
uh and then that's going to be read count equals
1:01:04
z if read count is greater than or equal to packet read
1:01:10
limit and return it's over the limit if
1:01:16
steam. get available P2P packet
1:01:22
size is greater than zero
1:01:28
get a little bit of space here we want to read
1:01:34
P2P message
1:01:39
packet we going to have to create that to and then we'll do read all P2P
1:01:46
message packets and then read count plus one so read peer to-peer
1:01:53
message packet but we're also going to do the same for The Voice packets as
1:01:59
well we may as well just do that now packet size one so that's on channel
1:02:05
one and it should be the same more or
1:02:11
less it should pretty much be the same except here we want to have voice packet
1:02:17
message packet so then we can create that
1:02:22
function uh here message packet
1:02:29
yep our packet size and equals steam.
1:02:37
getet available uh on Channel
1:02:42
Zero packet size is greater than zero I'll give uh this
1:02:51
packet dictionary equals steam. read P2 P
1:02:58
packet uh packet size and then on Channel
1:03:07
Zero then sender equals this
1:03:15
packet remote St ID our packet
1:03:23
code is a packed by array equals this
1:03:31
packet data bar
1:03:36
readable data
1:03:42
dictionary I need to convert that on
1:03:48
bites packet code yep if readable data do has
1:03:58
message then we want to match you know I love my
1:04:07
match message and if that's the handshake that we set from
1:04:15
before then print
1:04:21
player uh readable data username
1:04:30
name here space has
1:04:36
joined that's joined there we go an exclamation mark just for fun then
1:04:44
we want to get the lobby members there cool so then we need to do the
1:04:51
same but we have to do it for the peer to-peer packet so again this goes back
1:04:59
to this tutorial um and a lot of that stuff is
1:05:05
in here but then there's a lot of stuff that we need to add to the player as well so we're just going to continue
1:05:10
along here which is the read peer to-peer voice
1:05:19
packet and then I'm going to go the same as before our packet size if it's more
1:05:25
than that then we go up to here change that to one
1:05:30
because we're on channel one and then we're going to want to change this one as well cuz we're on channel one uh we don't want to mix our voice
1:05:38
peer-to-peer um packet stuff with uh anything else any of the messages or
1:05:43
what else we want to put on um Channel Zero which is the default so we'll just do all our voice on channel
1:05:49
one uh then we want to get the packet sender the readable data as well
1:05:56
um and the code so all of that looks pretty good
1:06:03
then we go if readable
1:06:10
data has voice
1:06:15
data then print uh yeah
1:06:23
reading go readable data uh
1:06:32
username voice data just for testing so we can see if we're actually reading the
1:06:37
voice data or not so V plays in scene and so we're going to need to get
1:06:44
a reference to all the players in the scene and then we're going to want to send our voice data to that player we're
1:06:50
talking about the actual instance of the player because the proximity chat is going to come from the player itself so
1:06:57
we're going to find that now no in group
1:07:02
players and then for player in players
1:07:08
insane I'm going to need to check so if player do steam
1:07:15
ID equals packet sender and
1:07:22
player process voice data readable so we don't have that yet
1:07:28
we're going to need to make that readable data and then networks it's not local it's Network so like I said it
1:07:35
goes back to the tutorial about how to actually process this voice data um but
1:07:41
this tutorial doesn't really finish what to do with it it gets to the local sort of loop back but um it's what you
1:07:48
do LS if voice Source equals Network so we're creating that Network here uh and
1:07:54
we're going to copy this as well but we're going to turn local loop back off cuz we don't really need it and that's just being able to hear your own voice
1:08:00
from your player in game and then from
1:08:06
there else pass I think just for now
1:08:12
um otherwise we can put in you know some sort of error checking or something there cool so I think that's most of the
1:08:20
hard work done in there for the voice stuff we've just got to make it work so first of all we got to create this
1:08:26
process voice data um function over in the player
1:08:32
so Funk process voice data uh and that's going to be uh voice data the
1:08:44
dictionary uh voice source which you know we kind to have in
1:08:49
there as Network or local uh I'll just avoid that why not
1:08:54
and we'll pass that for for now um so as long as that's in there we then need to
1:09:00
have a function for recording the voice so record voice we'll do that just
1:09:08
now we'll have to set up a button for it as well is recording work that into the
1:09:14
logic avoid that too
1:09:19
steam set iname voice speaking uh steam manager and then we
1:09:27
get the steam ID and then is
1:09:33
recording and then we go who's recording we'll handle that
1:09:39
somewhere else and then go steam so start voice
1:09:46
recording easy as that I wish let's get the rest of it done stop
1:09:53
voice recording cool so there is a little bit of a delay I think in that stop voice recording um
1:09:59
you can read it in the docs I think it's because most people let go of the recording button uh before
1:10:05
they're done actually talking so I'm not sure how long it is I think it's like half a second or something but something
1:10:12
interesting I found in the docs anyway and before we can make the
1:10:18
process voice data we've actually got to come up to the top and add a bunch of
1:10:23
variables in there so so most of this I'm pretty sure you can just pinch from
1:10:30
here um in fact that's just what we're going to do now but it needs a little bit of work so this pull bite array
1:10:37
you'll notice needs to be changed to the packed bite array um I'm not sure why the document I guess they just didn't
1:10:44
realize but either way you've got to switch that over so what's that the current sample rate uh loot back local
1:10:51
playback and so the loot back we're just going to keep on false we don't care about that for
1:10:57
now um and now that we've got that we can actually do the process
1:11:03
voice function but we've also got to add in somehow a key to actually record your
1:11:10
voice so I just go Funk input here input event and then we can add
1:11:17
something in there for it so what's our voice recording button voice record
1:11:25
and we're going to add that in there and then we'll put it on the letter v v for
1:11:31
voice remember that one cool so first things first we want to
1:11:38
if is multiplayer Authority and
1:11:43
return and then further down we're going to need to add the pro chart
1:11:48
stuff so this would be if input do is action uh just
1:11:56
pressed uh and what do we call it voice record voice record yep then record voice equals true or
1:12:05
record voice true else L
1:12:10
if and that's going to be on the
1:12:16
release just release the voice record and I'm going to set that to
1:12:23
false cool so we won't really have any visual way of checking that for now but we'll be able to hear it and that's good
1:12:29
enough so first we need to create a check for voice function so it's just
1:12:35
going to check for it's running like a steam get available voice but we've got to actually put it somewhere
1:12:41
so where's our process I don't think we have process just yet so we'll go
1:12:48
Funk process and then if is multiplayer Authority get used to typing that in
1:12:56
your player functions going to check for
1:13:03
voice yeah and sometimes I like to put the move and slide right here as
1:13:09
well um just so the physics are processed here but it's happened like every frame it's kind of cool but I'm
1:13:15
not going to do it here check the voice so now we've got to create that function so Funk check for
1:13:23
voice um and then we're going to void
1:13:31
that and we go for available voices so we're going to get this from
1:13:38
steam or available voice equals
1:13:43
steam do get available
1:13:49
voice uh yep and we're going to call that so if available voice
1:13:55
uh result equals steam. vo
1:14:03
result voicer voice result
1:14:09
okay and available voice uh
1:14:16
buffer two FS wrong spot is greater than
1:14:22
zero and for our voice datter
1:14:28
dictionary equals steam. get
1:14:34
voice and if voice data uh
1:14:41
result equals steam voice result
1:14:49
okay yeah same one
1:14:57
uh and then we go steam
1:15:02
manager let's send the voice data so we're finally sending the voice
1:15:10
data buffer sending the buffer from the voice data that we're getting
1:15:16
from Steam if has loot back so not that we have it but we go process voice data
1:15:25
go voice data and local cool so that's our our loot back
1:15:31
so if we wanted to hear our own voice on our own computer but we have that turned off at the moment so that's not going to
1:15:37
do anything cool so that's sending the voice data um and then we need to
1:15:43
process the voice data so that's going to be a little bit more complicated but we'll just get
1:15:49
started so we got to get the sample rate that's the first thing that we have to do so we've got to create that function
1:15:56
real quick uh so we'll do this down the bottom fun get sample
1:16:02
rate is toggled equals
1:16:07
true and that's a void as well so
1:16:15
if is toggled then we go current sample rate
1:16:21
which is something we've declared at the top equals steam.
1:16:27
Geto optimal sample rate so this is one thing that they recommend that you do uh
1:16:33
if you don't want it to sound like really roboty and then we go the current sample
1:16:41
rate equals uh 4800 just in case set it back to normal
1:16:48
so um now we've got this stuff at the top which is our
1:16:55
stuff here but we've got to actually add a little bit more in which
1:17:01
is um yeah we'll figure this out cool so I guess we've got to actually
1:17:08
set the sample rate of our audio players so we've got Pro Network and proc local
1:17:13
and they're going to be in the same position we set that up a little bit higher so it comes from around the
1:17:20
face Maybe from around the mouth even where you can actually see them from
1:17:26
yeah that'll do cool and then we're going to drag that in so we've got a reference to
1:17:32
it now proc Network and proc local we can come back down to here remember we've got generators on
1:17:39
these so on the get sample rate here we can go pro Network and proc
1:17:47
local Dot and so you can hold alt by the way to type in more than one place at
1:17:53
once stream do mix rate equals current sample
1:18:01
rate cool and then um we could print the current sample rate but we don't have to
1:18:06
right now just it should just work cool so we've got a current sample rate in
1:18:12
our what's it called process voice data course so that's the first
1:18:17
step let's get the rest of this done so via decompress voice we got to decompress it
1:18:29
dictionary if voice Source equals we'll start with
1:18:35
local decompressed voice equals
1:18:41
steam. decompress voice we want to put the
1:18:49
voice St in here and get the buffer
1:18:55
and at the current sample rate cool so that's the decompressing uh voice
1:19:02
function really good for steam really cool so then we need to check if it's
1:19:09
Network I'm going to a buffer with two Fs in the right spots thank you very
1:19:16
much local no well this is the the local buffer so this actually needs to be the
1:19:22
voice data from the packet and current sample rate yeah because uh
1:19:28
we've actually sent that remember from uh earlier into this player uh to process the voice data with
1:19:36
network cool and so that was done with a uh voice uh data yep from
1:19:45
before cool so process voice data now the next thing we've got to
1:19:51
do we've decompressed voice uh
1:19:57
result equals steam. voice result
1:20:03
okay and decompressed voice uh uncompressed size so we've got
1:20:10
to get the move that decompressed voice
1:20:15
uncompressed do size is greater than
1:20:21
zero um then we can move on so what's going on here is this all
1:20:28
right okay yeah this is cool yeah all right let just breaking cuz we're getting
1:20:34
ahead uh so then we can move on so if voice Source equals
1:20:41
local right then we can do the local loop back which is basically what they show you how to do what gramp shows you
1:20:48
how to do here um so we're essentially just going to type this out uh
1:20:56
uh yeah we just type it out yeah why not because I think we've actually made some
1:21:03
changes local voice buffer equals decompress The
1:21:10
Voice uh uncompressed uncompressed yep and then
1:21:18
local voice buffer when you're
1:21:23
resized d compressed voice uncompressed do size huh thank
1:21:32
you a voice buff all right now here comes the complicated
1:21:37
I and range zero to
1:21:46
mini local playback got get frames available
1:21:56
2 local voice buffer
1:22:03
size uh and then two so that should work just here and
1:22:10
then if we pass that make sure we've got no errors two but received three okay
1:22:17
what's going on here I think we needed to put that there and this here yeah there we go thought we were
1:22:24
going to have have issues there uh raw value int equals
1:22:33
local voice buffer zero PIP IT local voice
1:22:43
buffer number one and then give it one of
1:22:50
these then ra value
1:22:56
equals R Value Plus bunch of magic
1:23:03
numbers and ZX f f FF to B stuff thank
1:23:13
you and then we get the
1:23:19
amplitude the amplitude real quick the float
1:23:25
equals float uh raw value uh take away
1:23:34
32768 ided 327680 just Bay stuff that's what I call
1:23:41
this local playback push frame and we want that as
1:23:48
a vector 2 yep amplitude
1:23:54
and amplitude push that frame that's an
1:23:59
interesting one isn't it local voice buffer the remove
1:24:07
at zero I want to do that
1:24:12
twice just for good luck why not uh does he do that twice actually in
1:24:19
the tutorial yeah he does it twice I'm not sure why but we're going to do it twice as well
1:24:26
who am I to say he's wrong so then if it's
1:24:33
network if it's Network now we're going to handle it
1:24:39
Network Styles so decompress voice this is the same except it's Network voice
1:24:50
buffer Network voice buffer Network voice buffer yep
1:24:55
and then I'm pretty sure this is the same as well get frames available mini range we
1:25:02
need to make sure that this is actually the same we're going to cook ourselves
1:25:09
here ra value is this all the same network playback push frame yeah
1:25:17
this all looks exactly the same so I'm just going to copy oh local playback yeah some of this
1:25:24
stuff isn't the same though that's the problem so we just need to change this
1:25:33
over uh what do you mean local playback
1:25:40
okay Network playback thank you network playback Network playback
1:25:47
local voice buffer so we need can Network voice buffer
1:26:01
yep need to make sure all of this is network network
1:26:07
network y I don't like to copy things so need to make sure that these are all
1:26:13
network network a network
1:26:19
playback all right cool so that should work too now just like that
1:26:25
and now the next thing we've got to do is go to the project settings and then type um it's like microphone input enable
1:26:34
input so then we got to save and restart so I'll just do that cool so we're back the next thing you've got to do is uh
1:26:41
get rid of this null stuff here so the local playback and the network playback we've actually got to set up in the
1:26:48
ready um otherwise we're going to get an error so we just do that
1:26:56
here um I think we just we do it at the top because it doesn't really matter we've just got to make sure that it's
1:27:01
running on every single system that it's on so um we need to do a couple of things
1:27:09
so if we have two of
1:27:16
these Network playback so no we don't need that all right a pro local
1:27:27
stream miix rate equals current sample rate we've
1:27:33
just got to do that first and we'll do that to the network
1:27:39
too Network yep so and then on procs local we want to play so we need to make
1:27:45
sure that these uh these audio players are actually playing and then local playback
1:27:52
equals Pro local doget stream
1:27:58
playback yep and then we need to do the stuff with the network as well so we go proc
1:28:04
Network do playay and then we what's it called uh
1:28:10
Network playback dopr local no prox network
1:28:18
sorry um doget stream playback
1:28:26
uh okay I'll putting a dot in there instead get stream playback cool
1:28:33
beautiful and I know that I said that we weren't going to use the loot back but
1:28:38
we're just going to try that now just for testing so uh once we're in we should just be able to hold down V and
1:28:44
hear our voice post test test test test test cool
1:28:50
so that's coming through on mine test test test test test test test
1:28:56
test test test test test test test test test test test test that's actually
1:29:03
coming through the game when I hold down the V key so that's called local loot back test local loot back test
1:29:10
test cool so now that we know that that works um it should be that the multiplayer works as well so we're just
1:29:17
going to test that going to export the game we're going to see what happens but first i'm going to turn off local loop
1:29:24
back because we don't want to hear that while we listen to someone else exporting the
1:29:31
project and then I'm just going to copy that to my laptop okay now I've got the game up and running we've got another
1:29:37
user in the lobby and I'm just going to mute myself and show you what it looks like test test test test test test test
1:29:45
test test testest got a lot of feedback coming through
1:29:50
but should be working test you're working pretty
1:29:58
good working all right oh and I've just ping down I'm
1:30:07
falling all right cool so it works that's how you do your voice chat in uh
1:30:13
Gau so if you like the tutorial um check out
1:30:19
unaccessible on Steam oh support me directly
1:30:24
uh you can also join the Discord come hang out and ask me questions and blah blah blah blah blah and I'll probably
1:30:30
put the full code to this on the patreon eventually which I'll have the link for in the comments anyway thanks

