    /*

                   Fourmilab Target

                    by John Walker

        The target is designed to cooperate with Fourmilab
        projectiles such as those thrown by the Anvil Tosser,
        but will work with any projectiles.


    */

    string Bomb_explosion = "Bomb explosion";   // Bomb explosion sound clip
    string Target_marker = "Fourmilab Target Marker";   // Target marker object
    string helpFileName = "Fourmilab Target User Guide";    // Help notecard name
    integer hitChannel = -982449712;            // Channel for announcing hits (0 to suppress)

    integer commandChannel = 1308;  // Command channel in chat
    integer commandH;           // Handle for command channel
    key targetKey;              // Key of target
    key whoDat = NULL_KEY;      // Avatar who sent command
    key owner;                  // UUID of owner

    integer trace = FALSE;      // Trace mode output
    integer flash = TRUE;       // Show particle system explosion on impact
    integer bang = TRUE;        // Play explosion sound clip on impact
    integer legend = TRUE;      // Display floating text legend with scores ?

    /*  Standard colour names and RGB values.  The first 8
        colours have the indices of the classic AutoCAD
        colour palette.  */

    list colours = [
        "black",   <0, 0, 0>,       // 0
        "red",     <1, 0, 0>,       // 1
        "yellow",  <1, 1, 0>,       // 2
        "green",   <0, 1, 0>,       // 3
        "cyan",    <0, 1, 1>,       // 4
        "blue",    <0, 0, 1>,       // 5
        "magenta", <1, 0, 1>,       // 6
        "white",   <1, 1, 1>,       // 7

        /*  We fill out 8 and 9, which are also white in the
            AutoCAD palette, with useful colours accessible
            with a single digit index.  These are defined
            as in HTML5.  */

        "orange",  <1, 0.647, 0>,   // 8
        "grey",    <0.5, 0.5, 0.5>  // 9
    ];

    vector targetPos;           // Location of target centre
    float targetRadius;         // Radius of target
    list knownUsers = [];       // Map of UUIDs to known user names
    list pendingLookups = [];   // Owner name lookups pending
    key lastCollision = NULL_KEY;   // Last object we collided with

    //  tawk  --  Send a message to the interacting user in chat

    tawk(string msg) {
        if (whoDat == NULL_KEY) {
            //  No known sender.  Say in nearby chat.
            llSay(PUBLIC_CHANNEL, msg);
        } else {
            llRegionSayTo(whoDat, PUBLIC_CHANNEL, msg);
        }
    }

    //  onoff  --  Express a Boolean argument as "off" or "on"

    string onoff(integer b) {
        string s = "off";
        if (b) {
            s = "on";
        }
        return s;
    }

    //  abbrP  --  Test if string matches abbreviation

    integer abbrP(string str, string abbr) {
        return abbr == llGetSubString(str, 0, llStringLength(abbr) - 1);
    }

    //  onOff  --  Parse an on/off parameter

    integer onOff(string param) {
        if (abbrP(param, "on")) {
            return TRUE;
        } else if (abbrP(param, "of")) {
            return FALSE;
        } else {
            tawk("Error: please specify on or off.");
            return -1;
        }
    }

    //  processCommand  --  Process a command

    processCommand(key id, string message) {

        whoDat = id;            // Direct chat output to sender of command

        string lmessage = llToLower(llStringTrim(message, STRING_TRIM));

        //  Translate the curious commands from the dialogue to civilised tongue

        if (lmessage == "bang on") {
            lmessage = "set bang on";
        } else if (lmessage == "bang off") {
            lmessage = "set bang off";
        } else if (lmessage == "flash on") {
            lmessage = "set flash on";
        } else if (lmessage == "flash off") {
            lmessage = "set flash off";
        }  else if (lmessage == "legend on") {
            lmessage = "set legend on";
        } else if (lmessage == "legend off") {
            lmessage = "set legend off";
        }

        tawk(">> " + message);                      // Echo command to sender

        list args = llParseString2List(lmessage, [" "], []);    // Command and arguments
        integer argn = llGetListLength(args);
        string command = llList2String(args, 0);    // The command
        string param = "";
        if (argn > 1) {
            param = llList2String(args, 1);
        }

        //  If command is Clear for <key>, take ID from argument 2

        if (abbrP(command, "cl") && abbrP(param, "fo") && (argn > 2)) {
            command = "clear";
            param = "";
            argn = 1;
            whoDat = id = llList2Key(args, 2);
        }

        /*  These commands may be submitted by anybody who has
            hits posted on the target.  */

        integer u;

        for (u = 0; u < llGetListLength(hitList); u += 6) {
            if (llList2Key(hitList, u) == id) {
                jump foundu;
            }
        }
        u = -1;
        @foundu;

        //  Clear                   Clear requester's score

        if (abbrP(command, "cl") && (param == "")) {
            if (u >= 0) {
                hitList = llDeleteSubList(hitList, u, u + 5);
                if (legend) {
                    string hl = showHitList();
                    llSetLinkPrimitiveParamsFast(LINK_THIS,
                        [ PRIM_TEXT, hl, <0, 1, 0>, 1 ]);
                }
           } else {
                tawk("You have no score posted on the target.");
            }
            return;

        //  Help                    Give help information

        } else if (abbrP(command, "he")) {
            llGiveInventory(whoDat, helpFileName);
            return;

        //  Scores                  Show hit list

        } else if (abbrP(command,  "sc")) {
            string hl = showHitList();
            if (llStringLength(hl) > 0) {
                tawk("Top scores:\n" + hl);
            } else {
                tawk("No scores.");
            }
            return;
        }

        //  The following commands are restricted to the owner only

        if (whoDat != owner) {
            tawk("You do not have permission to control this object.");
            return;
        }

        /*  Channel n               Change command channel.  Note that
                                    the channel change is lost on a
                                    script reset.  */

        if (abbrP(command, "ch")) {
            integer newch = (integer) llList2String(args, 1);
            if ((newch < 2)) {
                tawk("Invalid channel " + (string) newch + ".");
            } else {
                llListenRemove(commandH);
                commandChannel = newch;
                commandH = llListen(commandChannel, "", NULL_KEY, "");
                tawk("Listening on /" + (string) commandChannel);
            }

        //  Clear all               Reset all score information

        } else if (abbrP(command, "cl") && abbrP(param, "al")) {
            hitList = [];               // Clear the hit list
            if (legend) {
                string hl = showHitList();
                llSetLinkPrimitiveParamsFast(LINK_THIS,
                    [ PRIM_TEXT, hl, <0, 1, 0>, 1 ]);
            }
            /*  We don't clear the knownUsers because that is simply a map
                of keys to user names, and that is not going to change.  */

        //  Restart                 Perform a hard restart (reset script)

        } else if (abbrP(command, "re")) {
            llResetScript();            // Note that all global variables are re-initialised

        //  Set                     Set parameter

        } else if (abbrP(command, "se")) {
            string svalue = llList2String(args, 2);

            if (abbrP(param, "ba")) {           // Bang on/off
                bang = onOff(svalue);

            } else if (abbrP(param, "fl")) {    // Flash on/off
                flash = onOff(svalue);

            } else if (abbrP(param, "le")) {    // Legend on/off
                legend = onOff(svalue);
                if (legend) {
                    string hl = showHitList();
                    llSetLinkPrimitiveParamsFast(LINK_THIS,
                        [ PRIM_TEXT, hl, <0, 1, 0>, 1 ]);
                } else {
                    llSetLinkPrimitiveParamsFast(LINK_THIS,
                        [ PRIM_TEXT, "", <0, 1, 0>, 0 ]);
                }

            } else if (abbrP(param, "tr")) {    // Trace on/off
                trace = onOff(svalue);
            } else {
                tawk("Unknown variable \"" + param +
                    "\".  Valid: bang, flash, legend, trace.");
            }

        //  Stat                    Print current status

        } else if (abbrP(command, "st")) {
            string stat = "Target status:\n";
            stat += "    Position: " + (string) llGetPos() + "\n" +
                    "    Known users: " + llList2CSV(knownUsers) + "\n" +
                    "    Hit list: " + llList2CSV(hitList) + "\n" +
                    "    Bang: " + onoff(bang) +
                        "  Flash: " + onoff(flash) +
                        "  Legend: " + onoff(legend) +
                        "  Trace: " + onoff(trace) + "\n";
            integer mFree = llGetFreeMemory();
            integer mUsed = llGetUsedMemory();
            stat += "    Script memory.  Free: " + (string) mFree +
                    "  Used: " + (string) mUsed + " (" +
                    (string) ((integer) llRound((mUsed * 100.0) / (mUsed + mFree))) + "%)";
            tawk(stat);

        //  Test n                  Run built-in test n

/*
        } else if (abbrP(command, "test")) {
            integer n = (integer) llList2String(args, 1);
            if (n == 1) {
            } else if (n == 2) {
            } else if (n == 3) {
            } else {
            }
*/
        } else {
            tawk("Huh?  \"" + message + "\" undefined.  Chat /" +
                (string) commandChannel + " help for the User Guide.");
        }
    }

    /*  The hitList records hits on the target.  An entry exists for
        each unique owner of objects which have hit.  Indices in the
        entry for an owner's hits are:

            0       Owner key
            1       Owner name
            2       Number of hits
            3       Total score
            4       Unix time of last hit
            5       Colour for impact markers
    */

    list hitList = [];

    integer timerTick = 30;         // Periodic scan for expired hit list items, seconds
    integer hitListTimeout = 300;   // Remove hit list items after seconds of inactivity

    //  Generate sound and light show for an impact

    integer exploding = FALSE;      // Explosion particle effect running ?

    splodey() {
        if (flash) {
            llParticleSystem([
                PSYS_SRC_PATTERN, PSYS_SRC_PATTERN_EXPLODE,

                PSYS_SRC_BURST_RADIUS, 1,

                PSYS_PART_START_COLOR, <1, 1, 1>,
                PSYS_PART_END_COLOR, <1, 0.3, 0.3>,

                PSYS_PART_START_ALPHA, 1,
                PSYS_PART_END_ALPHA, 0.0,

                PSYS_PART_START_SCALE, <0.6, 0.6, 0>,
                PSYS_PART_END_SCALE, <0.1, 0.1, 0>,

                PSYS_PART_START_GLOW, 1,
                PSYS_PART_END_GLOW, 0,

                PSYS_SRC_MAX_AGE, 5,
                PSYS_PART_MAX_AGE, 3,

                PSYS_SRC_BURST_RATE, 40,
                PSYS_SRC_BURST_PART_COUNT, 5000,

                PSYS_SRC_ACCEL, <0, 0, 0>,

                PSYS_SRC_BURST_SPEED_MIN, 2,
                PSYS_SRC_BURST_SPEED_MAX, 5,

                PSYS_PART_FLAGS, 0
                    | PSYS_PART_EMISSIVE_MASK
                    | PSYS_PART_INTERP_COLOR_MASK
                    | PSYS_PART_INTERP_SCALE_MASK
                    | PSYS_PART_FOLLOW_VELOCITY_MASK
            ]);
        }

        if (bang) {
            llPlaySound(Bomb_explosion, 1);
            exploding = TRUE;
            llSetTimerEvent(1);             // Start timer to cancel particle system
        }
    }

    /*  Compute miss distance from centre of target.

        The plane of the target is defined by its centre point
        targetPos and the normal vector to the plane, normal.
        The line containing the last velocity vector of the
        colliding object is given by vel, from llDetectedVel()
        and pos, from llDetectedPos().  The equation for a point
        on this line is then p = d * vel + pos, where d is a
        real number parameter.  We wish to solve for d where the
        line intersects the plane, which is given by:
            d = ((targetPos - pos) * normal) / (vel * normal)
        where "*" denotes vector dot product.  We then substitute
        d into the parametric equation for the line, yielding
        p, the intersection of the velocity vector with the
        plane.  The miss distance is just targetPos - p.  */

    float missDistance(vector pos, vector vel, integer cmm) {
        rotation trot = llList2Rot(llGetPrimitiveParams([ PRIM_ROTATION ]), 0);
        vector normal = <0, 0, 1> * trot;       // Normal vector to target plane
        vel = llVecNorm(vel);                   // Normalise incoming velocity vector
        /*  If the dot product of the velocity vector and the
            normal to the target plane is zero, the line and
            plane are parallel and either do not intersect or
            intersect everywhere. This shouldn't happen in the
            case of a detected collision, but just in case we
            check for it and return a missDistance of -1.  */
        float vel_dot_normal = vel * normal;
        if (vel_dot_normal == 0) {
            return -1;
        }
        float d = ((targetPos - pos) * normal) / (vel_dot_normal);  // Parameter of intersection with plane
        vector p = (d * vel) + pos;             // Intersection of plane and incoming velocity

        /*  If the incoming projectile has a very flat
            trajectory with respect to the plane of the target,
            due to the wonky imprecision of Second Life
            collision detection, it is possible the computed
            intersection point will be distant from the target.
            This just confuses people, so we put in the
            following hack: if the distance from the target
            centre to the computed intersection point is greater
            than the target radius, replace it with a new
            computed impact point at the target radius in the
            direction of the vector from the target centre to
            the original computed intersection point.  */

        float missd = llVecDist(p, targetPos);
        if (missd > targetRadius) {
            missd = targetRadius;
            p = targetPos + (llVecNorm(p - targetPos) * missd);
        }

        //  Place the target impact marker at the projected impact point

        llRezObject(Target_marker, p, ZERO_VECTOR, ZERO_ROTATION, cmm);
        return missd;
    }

    /*  Compute score from miss distance.  The target is divided
        into ten concentric rings from the centre to the
        radius.  The innermost scores 10 and the outermost 1.  */

    integer score(float missd) {
        integer decile =  10 - (integer) ((missd / targetRadius) * 10);
        if (decile == 0) {
            decile = 1;             // Impact was exactly on radius
        }
        return decile;
    }

    //  Record a hit in the hitList

    recordHit(key oKey, string oName, integer score, integer cmm, integer range) {
        integer t = llGetUnixTime();
        integer nhits;
        integer nscore;

        integer i;
        for (i = 0; i < llGetListLength(hitList); i += 6) {
            if (llList2Key(hitList, i) == oKey) {
                nhits = llList2Integer(hitList, i + 2) + 1;
                nscore = llList2Integer(hitList, i + 3) + score;
                integer ocol = llList2Integer(hitList, i + 5);
                //  If colour known for this user, continue to use it
                if (ocol != 1000) {
                    cmm = ocol;
                }
                hitList = llListReplaceList(hitList, [ nhits, nscore, t, cmm ],
                                            i + 2, i + 5);
                jump exists;
            }
        }
        //  New user: make entry for first hit
        nhits = 1;
        nscore = score;
        hitList += [ oKey, oName, nhits, score, t, cmm ];
    @exists;

        //  Report hit: total hits, score, and total score to projectile owner

        if (hitChannel != 0) {
//            llRegionSayTo(oKey, hitChannel, llList2Json(JSON_ARRAY,
//                [ "HIT", nhits, score, nscore, range, commandChannel, targetKey ]));
            llRegionSay(hitChannel, llList2Json(JSON_ARRAY,
                [ "HIT", oKey, nhits, score, nscore, range, commandChannel, targetKey ]));
        }

        //  Update hit list in floating text

        if (legend) {
            string hl = showHitList();
            llSetLinkPrimitiveParamsFast(LINK_THIS,
                [ PRIM_TEXT, hl, <0, 1, 0>, 1 ]);
        }
    }

    //  Show hit list as text

    string showHitList() {
        string s = "";

        integer i;

        /*  Sort the hitList in descending order of score. This
            is a dreaded bubble sort but, hey, how long is the
            hit list going to be, anyway?  */

        for (i = 0;  i < llGetListLength(hitList); i += 6) {
            integer j;

            for (j = i + 6; j < llGetListLength(hitList); j += 6) {
                if (llList2Integer(hitList, i + 3) <
                    llList2Integer(hitList, j + 3)) {
                    list il = llList2List(hitList, i, i + 5);
                    hitList = llListReplaceList(hitList, llList2List(hitList, j, j + 5), i, i + 5);
                    hitList = llListReplaceList(hitList, il, j, j + 5);
                }
            }
        }

        for (i = 0; i < llGetListLength(hitList); i += 6) {
            integer colidx = llList2Integer(hitList, i + 5);
            if (colidx == 1000) {
                colidx = 8;                     // Unknown projectiles marked in orange
            } else {
                colidx = (colidx / 100) % 10;
            }

            s += llList2String(hitList, i + 1) +
                 "  Hits " + (string) llList2Integer(hitList, i + 2) +
                 "  Score " + (string) llList2Integer(hitList, i + 3) +
                 "  " + llList2String(colours, colidx * 2) + "\n";
        }

        if (llStringLength(s) > 0) {
            s = llGetSubString(s, 0, -2);           // Delete trailing new line
        }

        return s;
    }

    default {

        on_rez(integer num) {
            llResetScript();                // Restore all defaults
        }

        state_entry() {
            targetKey = llGetKey();         // Remember our key
            owner = llGetOwner();
            llPreloadSound(Bomb_explosion);
            llParticleSystem([]);           // Make sure particle system is cancelled
            targetPos = llGetPos();         // Save target location
            vector targetSize = llGetScale();   // Get target size
            float dmax = targetSize.x;
            if (targetSize.y > dmax) {
                dmax = targetSize.y;
            }
            if (targetSize.z > dmax) {
                dmax = targetSize.z;
            }
            targetRadius = dmax / 2;

            //  Clear any displayed floating text
            llSetLinkPrimitiveParamsFast(LINK_THIS,
                [ PRIM_TEXT, "", <0, 1, 0>, 0 ]);

            //  Start listening on the command chat channel
            commandH = llListen(commandChannel, "", NULL_KEY, "");
            llOwnerSay("Listening on /" + (string) commandChannel);

            exploding = FALSE;
            lastCollision = NULL_KEY;
            llSetTimerEvent(timerTick);     // Set hit list expiration timer
        }

        /*  The listen event handler processes messages from
            our chat control channel.  */

        listen(integer channel, string name, key id, string message) {
//llOwnerSay("Listen channel " + (string) channel + "  id " + (string) id + "  msg " + message);
            if (channel == commandChannel) {
                processCommand(id, message);
            }
        }

        //  Process collision(s) with target

        collision_start(integer nCol) {
            integer i;

            targetPos = llGetPos();         // Update target location in case it's moved
            vector targetSize = llGetScale();   // Update target size in case it's changed
            float dmax = targetSize.x;
            if (targetSize.y > dmax) {
                dmax = targetSize.y;
            }
            if (targetSize.z > dmax) {
                dmax = targetSize.z;
            }
            targetRadius = dmax / 2;

            for (i = 0 ; i < nCol; i++) {
                key whoId = llDetectedKey(i);
//llOwnerSay("whoId " + (string) whoId + "  lastCollision " + (string) lastCollision);
                if (whoId != lastCollision) {
                    lastCollision = whoId;
                    string what = llDetectedName(i);
//llOwnerSay("What " + what);
                    key ownerK = llDetectedOwner(i);
                    vector where = llDetectedPos(i);

                    /*  If the impactor name contains the code:
                            "P=<x,y,z>, "
                        parse the vector and save as the position from
                        which the impactor was thrown, for use in
                        subsequent range calculations.  */

                    integer range = -1;
                    integer w = llSubStringIndex(what, "P=<");
                    if (w > 0) {
                        integer e = llSubStringIndex(llGetSubString(what, w + 3, -1), ">, ") + w + 5;
//llOwnerSay("Whext = (" + llGetSubString(what, w, e) + ")  Vec = " + llGetSubString(what, w + 2, e - 2));
                        vector whence = (vector) llGetSubString(what, w + 2, e - 2);
                        what = llDeleteSubString(what, w, e);
//llOwnerSay("WhatP (" + what + ")");
                        range = llRound(llVecDist(whence, targetPos));
//llOwnerSay("Whence " + (string) whence + "  Range " + (string) range);
                    }

                    /*  If the name of the impactor contains the code:
                            "CMM=cmm, "
                        parse the numeric argument and extract the
                        colour of the impact marker, c, and its time
                        to live, mm in seconds. Remove the code from
                        the name of the impactor.  */

                    integer cmm = 1000;                 // Default if not specified
                    w = llSubStringIndex(what, "CMM=");
                    if (w >= 0) {
                        integer e = llSubStringIndex(llGetSubString(what, w + 4, -1), ", ") + w + 5;
//llOwnerSay("Whcmm = (" + llGetSubString(what, w, e) + ")  Cmm = " + llGetSubString(what, w + 4, e - 2));
                        cmm = (integer) llGetSubString(what, w + 4, e - 2);
                        what = llDeleteSubString(what, w, e);
//llOwnerSay("WhatP (" + what + ")");
                    }
//llOwnerSay("CMM " + (string) cmm + "  What " + what);

                    /*  This is a little subtle.  If we have seen
                        this user previously and assigned a colour,
                        override the colour in the impactor with the
                        assigned colour.  This ensures that all
                        projectiles from this user, whatever their
                        kind, will be shown as impacts with the same
                        colour.  */

                    integer k;
                    for (k = 0; k < llGetListLength(hitList); k += 6) {
                        if (llList2Key(hitList, k) == ownerK) {
                            integer ocol = llList2Integer(hitList, k + 5);
                            if (ocol != 1000) {
                                //  If MM is 0, set back to default of 0
                                if ((cmm % 100) == 0) {
                                    cmm = 30;
                                }
                                cmm = (cmm % 100) + (((ocol / 100) % 10) * 100);
                            }
                            k = llGetListLength(hitList) + 1;
                        }
                    }

                    /*  If, after all this we have still not determined cmm,
                        this is a non-cooperating impactor from a user we
                        haven't seen before.  Walk through the hit list
                        excluding colours already in used by users on it
                        and choose the highest numbered colour not already
                        used by somebody on the hit list.  We assign colours
                        from the top down to minimise the probability of
                        conflict with co-operating projectiles which start
                        from the bottom up.  */

                    if (cmm == 1000) {
                        list candColour = [ ];          //  List of candidate colours
                        for (k = 0; k < llGetListLength(colours); k++) {
                            candColour += k;
                        }
                        for (k = 0; k < llGetListLength(hitList); k += 6) {
                            integer ocol = llList2Integer(hitList, k + 5);
                            if (ocol != 1000) {
                                //  If MM is 0, set back to default of 0
                                if ((cmm % 100) == 0) {
                                    cmm = 30;
                                }
                            }
                            ocol /= 100;
                            integer l = llListFindList(candColour, [ ocol ]);
                            if (l >= 0) {
                                candColour = llDeleteSubList(candColour, l, l);
                            }
                        }
                        if (llGetListLength(candColour) > 0) {
                            cmm = (llList2Integer(candColour, -1) * 100) + 30;
                        } else {
                            cmm = 0;
                        }
//llOwnerSay("Candidate colours: " + llList2CSV(candColour) + " chose " + (string) (cmm / 100));
                    }


                    float miss = missDistance(where, llDetectedVel(i), cmm);

                    /*  Walk through the knownUsers list and see if
                        we've encountered this owner before.  If so,
                        we know the name.  */

                    integer j;
                    integer found = FALSE;
                    string ownerN;
                    for (j = 0; !found && (j < llGetListLength(knownUsers)); j += 2) {
                        if (llList2Key(knownUsers, j) == ownerK) {
                            ownerN = llList2String(knownUsers, j + 1);
                            found = TRUE;
                        }
                    }

                    if (found) {
                        recordHit(ownerK, ownerN, score(miss), cmm, range);
                    } else {
                         /*  We want to find the owner name corresponding
                             to the ID of the new user.  We can't do this
                             synchronously.  We schedule an Agent Data
                             Request which will return the results to our
                             dataserver() event handler.  Since we can
                             have several requests pending simultaneously,
                             handling these is somewhat messy.  We add
                             the query ID and key of the user to a strided
                             list of pending requests.  When the answer
                             comes back, we look up the key and then
                             make an entry in another strided list of keys
                             and user names.  */

                        key owner_name_query;
                        owner_name_query = llRequestAgentData(ownerK, DATA_NAME);
                        pendingLookups += [ owner_name_query, ownerK, what, miss, cmm, range ];
                    }

                    splodey();
                }
            }
        }

        /*  The dataserver event processes replies to requests
            submitted to look up the name associated with new
            owner keys we've encountered.  We complete the
            impact event using the name received and enter the
            name and ID pair in the list of known IDs.  As this
            is presently for low-traffic venues, we do not purge
            these but simply accumulate them until the script is
            reset.  */

        dataserver(key queryid, string data) {
            /*  We have received the results of a user name
                query. Now we'll look it up in the
                pendingLookups list and, upon finding it, make
                an entry for the ID and user name in the
                userNames list.  We then complete logging of the
                pending impact.  */
            integer i;

            for (i = 0; i < llGetListLength(pendingLookups); i += 6) {
                if (llList2Key(pendingLookups, i) == queryid) {
                    //  If user has the ironic last name of "Resident", elide it
                    if (llGetSubString(data, -9, -1) == " Resident") {
                        data = llGetSubString(data, 0, llStringLength(data) - 10);
                    }
                    /*  Add the ID and user pair to the knownUsers list.  At
                        the moment we simply remember every user who has ever
                        visited our parcel.  We'll eventually prune these after
                        a period of inactivity.  */
                    knownUsers += [ llList2Key(pendingLookups, i + 1),
                                    data ];

//                  string who = llList2String(pendingLookups, i + 2);      // Name of impacting object
                    float miss = llList2Float(pendingLookups, i + 3);       // Miss distance
                    integer cmm = llList2Integer(pendingLookups, i + 4);    // Colour and TTL
                    integer range = llList2Integer(pendingLookups, i + 5);  // Range

                    //  Finally, log the impact with the user's name
                    recordHit(llList2Key(pendingLookups, i + 1), data, score(miss), cmm, range);

                    /*  Delete the 6-tuple for this query from pendingLookups.  */

                    pendingLookups = llDeleteSubList(pendingLookups, i, i + 5);
                    return;
                }
            }
            llOwnerSay("What?  Can't find query ID " + (string) queryid);
        }

        //  Cancel the particle system after it's done its thing

        timer() {
            if (exploding) {
                exploding = FALSE;
                llParticleSystem([]);
                llSetTimerEvent(timerTick);
            } else {
                lastCollision = NULL_KEY;       // Reset last collision UUID
            }

            /*  Scan the hitList and remove any entries which have
                expired due to inactivity.  */

            integer purged = FALSE;
            integer t = llGetUnixTime();
            integer i;
            for (i = 0; i < llGetListLength(hitList); i += 6) {
                if ((llList2Integer(hitList, i + 4) + hitListTimeout) <= t) {
                    hitList = llDeleteSubList(hitList, i, i + 5);
                    i -= 6;             // Adjust index to resume with item after deletion
                    purged = TRUE;
                }
            }
            if (purged && legend) {
                string hl = showHitList();
                llSetLinkPrimitiveParamsFast(LINK_THIS,
                    [ PRIM_TEXT, hl, <0, 1, 0>, 1 ]);
            }
        }

        /*  When touched, display the dialogue.  The dialogue
            only contains owner-only buttons if we were touched
            by the owner.  */

        touch_start(integer i) {
            string dialogueMessage =  " ";          // Dialogue title

            key toucher = llDetectedKey(0);         // Avatar who touched us
            list dialogueButtons = [];
            dialogueButtons += [ "Clear" ];
            dialogueButtons += [ "Scores" ];
            dialogueButtons += [ "Help" ];
//llOwnerSay("Toucher " + (string) toucher + "  Owner " + (string) owner);
            if (toucher == owner) {
                dialogueButtons += [ "Clear all" ];
                dialogueButtons += [ "Status" ];
                if (bang) {
                    dialogueButtons += [ "Bang off" ];
                } else {
                    dialogueButtons += [ "Bang on" ];
                }
                if (flash) {
                    dialogueButtons += [ "Flash off" ];
                } else {
                    dialogueButtons += [ "Flash on" ];
                }
                if (legend) {
                    dialogueButtons += [ "Legend off" ];
                } else {
                    dialogueButtons += [ "Legend on" ];
                }
            }
            llDialog(toucher, dialogueMessage, dialogueButtons, commandChannel);
        }

    }
