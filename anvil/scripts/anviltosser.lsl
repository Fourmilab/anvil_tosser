    /*
                Fourmilab Anvil Tosser

                    by John Walker

        The Anvil Tosser is a wearable object which, responding
        to clicks in mouselook mode, throws Anvil Toss
        Projectile objects in the specified direction.  The
        Anvil Tosser cooperates with other Anvil Tossers in the
        vicinity to choose a unique impact marker colour for
        each user and with Fourmilab Target objects to receive
        impact and score information which is made available to
        the wearer.

    */

/* IF TRACE
    integer trace = FALSE;               // Trace operations
/* END TRACE */

    integer SPEED = 20;                 //  Speed of projectile in metres/sec
    integer LIFETIME = 15;              //  Life of projectiles in seconds
    integer impactMarkerLife = 30;      //  Life of impact markers in seconds
    integer buoyancy = 5;               //  Buoyancy * 10 (9 represents 10)
    integer imColour = -1;              //  Impact marker colour (-1 = none yet chosen)
    float DELAY = 0.2;                  //  Delay between shots for rate of fire
    string Launch_sound = "Whoosh";     //  Sound played at launch
    string projectileName = "Anvil Toss Projectile"; // Inventory name of projectile we throw
    vector holdOrientation = < 0, PI_BY_TWO, PI >;  // Orientation in which launcher held by avatar
    integer reqPerms;                   // Permissions we request

    key owner;                          //  Owner UUID
    string ownerName;                   //  Name of owner

    integer attPerms = FALSE;           // Requesting permissions after attach ?
    integer have_permissions = FALSE;   /*  Indicates whether wearer has yet given permission
                                            to take over their controls and animation.  */

    integer armed = TRUE;               //  Used to impose a short delay between firings
    integer nshots = 0;                 //  Number of shots made

    string instruction_1 = "Use Mouselook to aim, left click to throw.";
    string instruction_2 = "Choose \"Detach\" from menu to take off.";
    string instruction_3 = "Touch anvil to clear score.";

    //  List of the priority in which we request colours
    list colourPriority = [ 7, 3, 2, 4, 8, 1, 5, 6, 9, 0 ];
    integer colourNegotationChannel = -982449710;   //  Channel for colour negotation messages
    integer excludedColours = 0;                //  Colours reported used by other instances

    integer hitChannel = -982449712;            // Channel where target announces hits
    integer T_nhits;                            // Total hits
    integer T_score;                            // Score for this hit
    integer T_nscore;                           // Total score for all hits
    integer T_range;                            // Range in metres (-1 if unknown)
    integer T_channel;                          // Target's command channel
    key T_key = NULL_KEY;                       // Target key

    /*  initTosser  --  Initialise the tosser.
                        Due to all the wondrous ways this script
                        can be initialised, which include:
                            on_rez()
                                When initially attached from
                                the inventory or when the avatar
                                appears following a viewer restart
                            state_entry()
                                When the script is reset after being
                                saved from an edit, or from the Edit
                                box
    */

    initTosser() {
        owner = llGetOwner();
        ownerName =  llKey2Name(owner);  //  Save name of owner
        llListen(colourNegotationChannel, "", "", "");  // Listen for colour negotation messages
        llRegionSay(colourNegotationChannel, llList2Json(JSON_ARRAY,
            [ "COLOURQ", ownerName ]));         //  Send colour query to other instances of ourself
        excludedColours = 0;                    // No colours yet excluded
        imColour = -1;                          // Set colour not yet chosen
        nshots = 0;                             // Zero shots taken
        T_key = NULL_KEY;                       // Target unknown
        llSetLinkPrimitiveParamsFast(LINK_THIS, // Clear any legend
            [ PRIM_TEXT, "", <0, 1, 0>, 0 ]);

        llListen(hitChannel, "", "", "");       // Listen for hit reports from target
        llPreloadSound(Launch_sound);           // Preload the launch sound

        //  If we are already attached to an avatar, request permissions

        if (llGetAttached() != 0) {
/* IF TRACE
            if (trace) {
                llOwnerSay("Attached at initialisation; requesting permissions.");
            }
/* END TRACE */
            have_permissions = FALSE;
            reqPerms = PERMISSION_TRIGGER_ANIMATION | PERMISSION_TAKE_CONTROLS;
            llRequestPermissions(llGetOwner(), reqPerms);
            llSetLinkPrimitiveParamsFast(LINK_THIS,     // Adjust hold orientation
                [ PRIM_ROT_LOCAL, llEuler2Rot(holdOrientation) ]);
        }
    }

    //  Choose a unique colour for our impact markers

    integer myColour() {
        if (imColour < 0) {
            /*  Walk through the colours in priority order and select
                the first for which we have not received an exclusion
                message from another instance.  */

            integer i;
            for (i = 0; i < llGetListLength(colourPriority); i++) {
                integer col = llList2Integer(colourPriority, i);
                if ((excludedColours & (1 << col)) == 0) {
                    imColour = col;
                    excludedColours = excludedColours | (1 << imColour);
                    i = llGetListLength(colourPriority) + 1;    // Escape for loop
                }

                if (imColour < 0) {
                    // All colours in use: re-use at random
                    imColour = llList2Integer(colourPriority,
                        (integer) llFrand(llGetListLength(colourPriority) + 1));
                }

                //  Inform peers we're now using this colour

                llRegionSay(colourNegotationChannel, llList2Json(JSON_ARRAY,
                    [ "COLOURU", ownerName, imColour ]));    //  Send colour we use to other instances
            }
        }
        return imColour;
    }

    //  Create a projectile and launch toward the target

    fire() {
        if (armed) {

            //  Switch to aim animation

            llStopAnimation("hold_R_handgun");
            llStartAnimation("aim_R_handgun");

            //  Fire the projectile

            rotation rot = llGetRot();      //  Get current avatar mouselook direction
            vector vel = llRot2Fwd(rot);    //  Convert rotation to a direction vector
            vector pos = llGetPos();        //  Get position of avatar to create projectile
            pos = pos + vel;                //  Create projectile slightly in direction of travel
            pos.z += 0.75;                  /*  Correct creation point upward to eye point
                                                from hips,  so that in mouselook we see projectile
                                                travelling away from the camera.  */

            /*  Create the actual projectile from object
                inventory, and set its position, velocity, and
                rotation.  Pass parameters encoding the
                properties of the projectile and impact marker.
                These are saved in the "fire" variables to be sent
                in the Launch message when the newly-rezzed
                projectile contacts us.  */

            if (imColour < 0) {
                imColour = myColour();
/* IF TRACE
                if (trace) {
                    llOwnerSay("Choosing colour " + (string) imColour + " for markers");
                }
/* END TRACE */
            }

            integer CMM = (SPEED * 1000000) +
                          (buoyancy * 100000) +
                          (impactMarkerLife * 1000) +
                          (imColour * 100) + LIFETIME;

            //  Create projectile

            llRezObject(projectileName, pos, ZERO_VECTOR, rot, CMM);
            llTriggerSound(Launch_sound, 1.0);  //  Start the sound of the projectile being shot

            nshots++;
            updateLegend();

            armed = FALSE;
            llSetTimerEvent(DELAY);
        }
    }

    //  pl  --  Pluralise a noun depending on value

    string pl(string noun, integer value) {
        if (value != 1) {
            return noun + "s";
        }
        return noun;
    }

    //  Update the floating text legend

    updateLegend() {
        if ((nshots + T_nhits + T_nscore) > 0) {
            string fl = (string) nshots + " " + pl("shot", nshots) + ", " +
                        (string) T_nhits + " " + pl("hit", T_nhits) + ", " +
                        "score " + (string) T_nscore;
            llSetLinkPrimitiveParamsFast(LINK_THIS,
                [ PRIM_TEXT, fl, <0, 1, 0>, 1 ]);
        } else {
                llSetLinkPrimitiveParamsFast(LINK_THIS,
                    [ PRIM_TEXT, "", <0, 1, 0>, 0 ]);
        }
    }

    //  Record a hit reported by the target

    recordHit(integer t_nhits, integer t_score, integer t_nscore, integer t_range) {
        string srange = "";
        if (t_range >= 0) {
            srange = "Range " + (string) t_range + " m  ";
        }
        llOwnerSay("Hit!  " + srange +
                   "Score " + (string) t_score +
                   "  Total hits " + (string) t_nhits +
                   " out of " + (string) nshots + " shots." +
                   "  Total score " + (string) t_nscore);
        updateLegend();
    }

    default {

        /*  Initial instantiation from inventory sends us
            an on_rez() message.  We will also receive an
            attach() message.  From experimentation, it
            appears that adding the object as an attachment
            sends on_rez() followed by attach(), while after
            a restart of the viewer with the object already
            attached, we receive attach() before on_rez().  We
            handle both cases, but do not count on the order
            of the messages.  */

        on_rez(integer param) {
/* IF TRACE
            if (trace) {
                llOwnerSay("on_rez()");
            }
/* END TRACE */
            initTosser();
        }

        /*  We must also initialise upon state_entry() because if
            the script is reset or edited and saved while attached,
            we receive only this event and must restore permissions
            and modes from their initial values.  */

        state_entry() {
/* IF TRACE
            if (trace) {
                llOwnerSay("state_entry()");
            }
/* END TRACE */
            initTosser();
        }

        /*  Attachment to or detachment from an avatar sends
            an attach() message.  Note, however, that resetting
            the script while the object is attached does not
            send an attach() message, just state_entry(), so we
            must determine whether we're attached at that time
            and initialise accordingly.  */

        attach(key attachedAgent) {
            if (attachedAgent != NULL_KEY) {
/* IF TRACE
                if (trace) {
                    llOwnerSay("attach to " + (string) attachedAgent +
                        " (" + llGetUsername(attachedAgent) + ")");
                }
/* END TRACE */
                /*  This is a new attachment.  We can receive
                    this message either when an avatar adds the
                    object as an attachment or after a viewer
                    restart.  After a viewer restart obtaining
                    permissions is wonky: doing it as you do for
                    a normal attach fails silently--it tells you
                    you have control permission, reports no error
                    on taking controls, but in fact you don't have
                    them and never receive control() messages.

                    To get around this, we have the following
                    horrible kludge.  First, we request permissions
                    normally, which works for an initial attachment.
                    Then we start a timer (the last resort of the
                    de-wonkifier) which polls llGetAgentInfo() to
                    see if we're in mouselook mode.  As soon as we
                    enter mouselook, we request permissions again,
                    which always seems to work.  This is the only
                    way I've found to guarantee controls are taken
                    in all circumstances.  */

                llRequestPermissions(llGetOwner(), reqPerms);

                attPerms = TRUE;
                llSetTimerEvent(1);
                llSetLinkPrimitiveParamsFast(LINK_THIS,     // Adjust hold orientation
                    [ PRIM_ROT_LOCAL, llEuler2Rot(holdOrientation) ]);
            } else {
                //  Detachment: stop animation and release controls
/* IF TRACE
                if (trace) {
                    llOwnerSay("Detached from avatar");
                }
/* END TRACE */
                if (have_permissions) {
                    llStopAnimation("hold_R_handgun");
                    llStopAnimation("aim_R_handgun");
                    llReleaseControls();
                    have_permissions = FALSE;
                }
            }
        }

        //  Upon receiving permissions, take controls and start hold animation

        run_time_permissions(integer permissions) {
            if ((permissions & reqPerms) == reqPerms) {
/* IF TRACE
                if (trace) {
                    llOwnerSay("run_time_permissions(" + (string) permissions + ")");
                }
/* END TRACE */
                if (!have_permissions) {
                    llWhisper(PUBLIC_CHANNEL, instruction_1);
                    llWhisper(PUBLIC_CHANNEL, instruction_2);
                    llWhisper(PUBLIC_CHANNEL, instruction_3);
                }
                llTakeControls(CONTROL_ML_LBUTTON, TRUE, FALSE);
                llStartAnimation("hold_R_handgun");
                have_permissions = TRUE;
            }
        }

        //  Avatar has clicked the left button in Mouselook mode

        control(key name, integer levels, integer edges) {
//llOwnerSay("Control levels " + (string) levels + "  edges " + (string) edges);
            if (((edges & CONTROL_ML_LBUTTON) == CONTROL_ML_LBUTTON) &&
                ((levels & CONTROL_ML_LBUTTON) == CONTROL_ML_LBUTTON)) {
                //  When left mouse button is pressed, fire projectile
                fire();
            }
        }

        //  When touched, reset number of shots taken

        touch_start(integer num) {
            /*  In some cases, for example when an avatar boards
                and subsequently leaves a vehicle, the vehicle may
                take and then release controls, which will cause
                us to lose access to the mouselook button control.
                To recover from this, we make touching the anvil
                restore our taking of the control and, for good
                measure, the hold animation in case it's been
                overridden.  This will also clear the scores, but
                so would detaching and reattaching the anvil, which
                is the only other way to get back the controls.  */
            llTakeControls(CONTROL_ML_LBUTTON, TRUE, FALSE);
            llStartAnimation("hold_R_handgun");

            nshots = T_nhits = T_nscore = 0;
            if (T_key != NULL_KEY) {
                llRegionSayTo(T_key, T_channel, "Clear for " + (string) owner);
            }
            updateLegend();
        }

        //  The listen event handles colour negotiation and target hit messages

        listen(integer channel, string name, key id, string message) {
//llOwnerSay("Message channel " + (string) channel + "  name " + name + "  id " + (string) id + "  message " + message);

            //  Message on colour negotiation channel

            if (channel == colourNegotationChannel) {
                list msg = llJson2List(message);
                string ccmd = llList2String(msg, 0);

                //  COLOURQ:  Colour used query--report our colour to others

                if (ccmd == "COLOURQ") {        // Colour used query
                    if (imColour >= 0) {        // If we have chosen a colour
                        llRegionSay(colourNegotationChannel, llList2Json(JSON_ARRAY,
                            [ "COLOURU", ownerName, imColour ]));    //  Send colour we use to other instances
/* IF TRACE
                        if (trace) {
                            llOwnerSay("Reporting our colour used: " + (string) imColour);
                        }
/* END TRACE */
                    }

                //  COLOURU:  Colour used report from others

                } else if (ccmd == "COLOURU") {        // Colour used report
                    integer ucol = (integer) llList2String(msg, 2);
/* IF TRACE
                    if (trace) {
                        llOwnerSay("Colour used: " + (string) ucol +
                            " by " + (string) id + " (" + llList2String(msg, 1) + ")");
                    }
/* END TRACE */
                    excludedColours = excludedColours | (1 << ucol);
                }

            //  Message on target hit report channel

            } else if (channel == hitChannel) {
                list msg = llJson2List(message);
                string ccmd = llList2String(msg, 0);

                //  HIT:  Hit report from target

                if (ccmd == "HIT") {
                    key T_okey = llList2Key(msg, 1);            // Key of projectile owner
                    if (T_okey == owner) {                      // Is is this a hit by us ?
                        T_nhits = llList2Integer(msg, 2);       // Total hits
                        T_score = llList2Integer(msg, 3);       // Score for this hit
                        T_nscore = llList2Integer(msg, 4);      // Total score for all hits
                        T_range = llList2Integer(msg, 5);       // Range of hit
                        T_channel = llList2Integer(msg, 6);     // Target's command channel
                        T_key = llList2String(msg, 7);          // Target key

                        recordHit(T_nhits, T_score, T_nscore, T_range);  // Record the hit for the user
                    }
                }
            }
        }

        /*  The timer() event is used to re-arm the launcher
            after the post-shot delay, and to poll for initial
            entry to mouselook mode and request permissions to
            work-around the failure to obtain permissions after
            the viewer restarts with the object attached.  */

        timer() {
            if (attPerms) {
                /*  We are waiting for initial mouselook entry.
                    If we're now in mouselook mode, make a final
                    request for permissions and terminate the poll.   */
                if (llGetAgentInfo(llGetOwner()) & AGENT_MOUSELOOK) {
                    llSetTimerEvent(0);
                    attPerms = FALSE;
/* IF TRACE
                    if (trace) {
                        llOwnerSay("Initial entry to mouselook: request permissions");
                    }
/* END TRACE */
                    llRequestPermissions(llGetOwner(), reqPerms);
                }
            } else {
                //  If this is expiration of delay after fire, re-arm
                if (!armed) {
                    //  Stop aim animation, resume hold animation
                    llStopAnimation("aim_R_handgun");
                    llStartAnimation("hold_R_handgun");
                    llSetTimerEvent(0);
                    armed = TRUE;
                }
            }
        }
    }
