    /*

                          Anvil Toss Projectile
                             by John Walker

        This is the projectile thrown by the Anvil Tosser.  It
        should not be confused with the Anvil Bomb which is
        dropped by the Rocket.  The two share the same mesh
        object, but the scripts are substantially different
        since this is a thrown ballistic projectile while the
        other is a gravity bomb.

        The projectile cooperates with Fourmilab Target objects
        to defer marking and scoring of impacts to the target.
        The projectile is instantiated with a start parameter
        which encodes items such as its colour, buoyancy, time
        to live, and the lifetime of the impact markers it places.

        When the projectile is instantiated, it is not a physical
        object and has zero velocity.  This is necessary because
        there can be an arbitrary delay between the time of
        instantiation and when this script actually begins to
        execute.  During that time, were the projectile physical
        and endowed with velocity, it would respond to gravity
        (before we get to set its buoyancy) and move with the
        initial velocity.  It is hence possible it may collide
        before we even get a chance to register our collision
        event or set the information needed by the target to score
        a hit.  To avoid this, we wait until our on_rez() event
        gets control, and only then make the projectile physical
        and set its velocity.  Because we can only pass an integer
        as the start_param, we recompute the velocity vector from
        the projectile's position and rotation, which were set when
        it was rezzed by the launcher.

        This program may be configured with Fourmilab's lslconf.pl
        utility to enable or disable the embedded trace code.

    */

    integer dynamic = FALSE;                // Were we rezzed by the launcher ?
    float SPEED = 20.0;                     // Speed of projectile in metres/sec
    float buoy = 0.5;                       // Buoyancy (flatness of trajectory)
    vector tumbleAxis = < PI_BY_TWO, -PI_BY_TWO, PI >;  // Axis of tumbling, ZERO_VECTOR disables
    float tumbleRate = PI;                  // Tumble rate, radians per second
    float tumbleGain = 1;                   // Tumble gain factor
    float pushImpulse = 2000;               // Impulse with which we push avatars
    string Collision = "Balloon Pop";       // Collision sound clip

    string impactMarker = "Fourmilab Impact Marker";    // Impact marker object from inventory
    string targetDesc = "Fourmilab Target";             // Description of cooperating target

    //  These are usually overridden by the CMM start_param in on_rez()
    integer time_to_live = 15;              // Lifetime of projectile if no impact (seconds)
    integer impactMarkerLife = 30;          // Lifetime of impact markers (seconds)
    integer colour;                         // Colour index of impact marker

    key myself;                             // Our own key
    key owner;                              // Key of our owner
    vector launchPos;                       // Location at launch
    integer impacted = FALSE;               // Have we already impacted an object ?
    integer hitGround = FALSE;              // Have we hit the ground ?
/* IF TRACE
    integer trace = FALSE;                  // Trace collision events ?
/* END TRACE */

    //  Create particle system for impact effect

    splodey() {
        llParticleSystem([
            PSYS_SRC_PATTERN, PSYS_SRC_PATTERN_EXPLODE,

            PSYS_SRC_BURST_RADIUS, 0.1,

            PSYS_PART_START_COLOR, <1, 1, 1>,
            PSYS_PART_END_COLOR, <1, 1, 1>,

            PSYS_PART_START_ALPHA, 0.9,
            PSYS_PART_END_ALPHA, 0.0,

            PSYS_PART_START_SCALE, <0.3, 0.3, 0>,
            PSYS_PART_END_SCALE, <0.1, 0.1, 0>,

            PSYS_PART_START_GLOW, 1,
            PSYS_PART_END_GLOW, 0,

            PSYS_SRC_MAX_AGE, 0.1,
            PSYS_PART_MAX_AGE, 0.5,

            PSYS_SRC_BURST_RATE, 20,
            PSYS_SRC_BURST_PART_COUNT, 1000,

            PSYS_SRC_ACCEL, <0, 0, 0>,

            PSYS_SRC_BURST_SPEED_MIN, 2,
            PSYS_SRC_BURST_SPEED_MAX, 2,

            PSYS_PART_FLAGS, 0
                | PSYS_PART_EMISSIVE_MASK
                | PSYS_PART_INTERP_COLOR_MASK
                | PSYS_PART_INTERP_SCALE_MASK
                | PSYS_PART_FOLLOW_VELOCITY_MASK
        ]);
    }

    //  Impact with an object

    impact(integer target, integer avatar, key what) {
        if (dynamic) {
/* IF TRACE
            if (trace) {
                llOwnerSay("    Impact: " + (string) what +
                    "  " + llKey2Name(what) +
                    " avatar? " + (string) avatar +
                    " target? " + (string) target);
            }
/* END TRACE */
            vector pos = llGetPos();
            /*  The following call cancels the object's velocity
                and moves it smoothly to the point of impact.
                This is necessary because otherwise a physical
                object may continue to fly and impact other objects.  */
            llMoveToTarget(pos, 0.1);
            /*  Marking the object phantom causes it to cease to
                interact with other objects until it is destroyed
                by the timer in a moment.  */
            llSetStatus(STATUS_PHANTOM, TRUE);

            /*  If the collision was not with a designated
                target, place an impact marker and indicate
                the impact with sound and particle effects.
                If we hit a target, let the target handle
                the theatrics.  */

            if (!target) {

                /*  If collision is with an avatar, administer a swift push.
                    We determine the direction and magnitude of the push
                    based upon the normalised direction vector from the
                    position of the impact and our launch position and the
                    pushImpulse parameter.

                    The rather complex way push permissions work complicates
                    this matter.  We only push if pushImpulse is nonzero.  If
                    the parcel is set to No Pushing, then the owner (or group
                    member if the parcel is group-owner) can push, but others
                    cannot.  We apply all of these rules to decide whether to
                    push or treat this as a regular impact with a non-target.  */

                if (avatar && (pushImpulse > 0) &&
                    (((llGetParcelFlags(pos) & PARCEL_FLAG_RESTRICT_PUSHOBJECT) == 0) ||
                     llOverMyLand(owner))) {
                    llPushObject(what, llVecNorm(pos - launchPos) * pushImpulse,
                        ZERO_VECTOR, FALSE);
                } else {

                    /*  This is a collision with an object which is
                        neither an avatar nor a target.  We wish to place
                        an impact marker at the point of impact, but this
                        poses a problem because the collision event doesn't
                        tell us that.  It will tell us the centre of mass
                        of the object we hit [llDetectedPos()], but that
                        may be distant from the point of impact.  Using the
                        current position of the object is much better, but
                        may still be off by quite a bit.

                        Much more precise localisation can be obtain through
                        ray casting [llCastRay()], which gives accurate
                        positions on both objects and terrain.  We project a
                        ray from our launch position to our current position,
                        post-impact, plus 10% further, looking for as many as
                        five intersections.  We then walk through these looking
                        for the one which has the same key as the object we've
                        hit.  Upon finding it, we use the ray intersection
                        point to place the impact marker.  */

                    /*  Cast a ray to try to find what we hit.  */

                    list hits = llCastRay(launchPos, pos + ((pos - launchPos) * 1.1),
                        [ RC_MAX_HITS, 5 ]);
                    if (llList2Integer(hits, -1) > 0) {
                        integer i;
                        integer rayhit = -1;
                        integer nhits = llList2Integer(hits, -1) * 2;

                        //  Find the ray that intersected the object we hit

                        for (i = 0; i < nhits; i += 2) {
                            key hitk = llList2Key(hits, i);
/* IF TRACE
                            if (trace) {
                                vector hp = llList2Vector(hits, i + 1);
                                string me = "";
                                if (hitk == myself) {
                                    me = " (me) ";
                                }
                                llOwnerSay("    Ray cast hit " + (string) ((i / 2) + 1) + " " +
                                    llKey2Name(hitk) + me +
                                    " key " + (string) hitk +
                                    " dist " + (string) llVecDist(pos, hp));
                            }
/* END TRACE */
                            if (hitk == what) {
                                rayhit = i;
                                i = nhits;          // Escape from loop
                            }
                        }

                        /*  If we found the object we hit in the ray
                            cast, adjust the position for the impact
                            marker to the ray intersection.  */
                        if (rayhit >= 0) {
                            pos = llList2Vector(hits, rayhit + 1);
                            /*  One more wrinkle: if the hit was on terrain,
                                offset the impact marker vertically so half
                                of it isn't embedded in the ground.  Where
                                did this screwball number come from, you ask?
                                Well, you see, while the star is centred
                                in the 0.5 metre square marker, its bottom
                                two points do not extend all the way to its
                                bottom.  This offset shifts the marker so
                                they touch the ground when the marker is
                                perpendicular to it.  */
                            if (llList2Key(hits, rayhit) == NULL_KEY) {
                                pos.z += 0.07672;
                            }
/* IF TRACE
                            if (trace) {
                                string oname = "[Ground]";
                                key k = llList2Key(hits, rayhit);
                                if (k != NULL_KEY) {
                                    oname = llKey2Name(k);
                                }
                                llOwnerSay("    Adjusting marker to ray hit " +
                                    (string) ((rayhit / 2) + 1) + " at " +
                                    (string) pos + " (" + oname + ")");
                            }
/* END TRACE */
                        }
                    } else {
/* IF TRACE
                        if (trace) {
                            llOwnerSay("    Ray cast failed, status: " +
                                (string) llList2Integer(hits, -1));
                        }
/* END TRACE */
                    }

                    /*  Back up a tad along the direction to the launcher
                        to avoid the impact marker's being swallowed by
                        the object we hit.  The offset is specified as an
                        absolute distance in metres, as it is relative to
                        the hit location, not the distance from the tosser.  */
                    pos -= llVecNorm(pos - launchPos) * 0.05;

                    /*  Compute rotation to point the face of the impact
                        marker toward the launch point.  We start by
                        finding the normalised direction vector from the
                        launch to impact point.  */
                    vector nvec = llVecNorm(launchPos - pos);
                    //  Now compose rotations to align the star, point up, toward the launcher
                    rotation storient = llAxisAngle2Rot(<1, 0, 0>, llSin(nvec.z) + PI_BY_TWO) *
                        llEuler2Rot(<0, 0, llAtan2(nvec.y, nvec.x) + PI + PI_BY_TWO>);

                    /*  Now we go a-ray casting again: this time looking down
                        (in region co-ordinates) to see if our impact marker
                        risks being swallowed by the ground or some object
                        (for example, a floor).  If so, shift it upward so
                        it clears the interference.  */

                    hits = llCastRay(pos, pos - <0, 0, 0.6>,
                        [ RC_MAX_HITS, 5 ]);
                    if (llList2Integer(hits, -1) > 0) {
                        integer i;
                        integer rayhit = -1;
                        integer nhits = llList2Integer(hits, -1) * 2;
                        float cdist = 1e30;

                        //  Find the ray that intersected the object below us

                        for (i = 0; i < nhits; i += 2) {
                            key hitk = llList2Key(hits, i);
                            vector hp = llList2Vector(hits, i + 1);
                            float hitd = llVecDist(pos, hp);
/* IF TRACE */
                            if (1) {
                                string me = "";
                                if (hitk == myself) {
                                    me = " (me) ";
                                }
                                llOwnerSay("    Ray cast hit " + (string) ((i / 2) + 1) + " " +
                                    llKey2Name(hitk) + me +
                                    " key " + (string) hitk +
                                    " dist " + (string) hitd);
                            }
/* END TRACE */
                            if ((hitk != myself) && (hitd < cdist)) {
                                rayhit = i;
                                cdist = hitd;
                            }
                        }

                        if (rayhit >= 0) {
                            //  Another magic number to offset so star sits on surface
                            pos = llList2Vector(hits, rayhit + 1) + <0, 0, 0.17328>;
/* IF TRACE */
                            if (1) {
                                llOwnerSay("Floor is " + (string) ((rayhit / 2) + 1) +
                                    " at " + (string) llList2Vector(hits, rayhit + 1));
                                string oname = "[Ground]";
                                key k = llList2Key(hits, rayhit);
                                if (k != NULL_KEY) {
                                    oname = llKey2Name(k);
                                }
                                llOwnerSay("    Adjusting marker to ground/obstruction hit " +
                                    (string) ((rayhit / 2) + 1) + " at " +
                                    (string) pos + " (" + oname + ")");
                            }
/* END TRACE */
                        }
                    } else {
/* IF TRACE
                        if (trace) {
                            llOwnerSay("    Ray cast failed, status: " +
                                (string) llList2Integer(hits, -1));
                        }
/* END TRACE */
                    }


                    /*  Place an impact marker where we hit.  The
                        marker is rotated so we're looking at it
                        face on.  */
                    llRezObject(impactMarker, pos, ZERO_VECTOR,
                        storient, (colour * 100) + impactMarkerLife);
                }
                llPlaySound(Collision, 1);
                splodey();
            }
            llSetTimerEvent(0.1);               // Start timer to die soon
        }
    }

    default {

        on_rez(integer CMM) {
            myself = llGetKey();
            owner = llGetOwner();

            dynamic = CMM != 0;                     // Mark if we were rezzed by the launcher

            if (dynamic) {
                launchPos = llGetPos();             // Save position at launch

                /*  Encoding of CMM:
                        SSBMMCTT

                        TT = Time to live, 0 - 99 seconds (0 = immortal)
                        C  = Colour index, 0 = white, 7 = black, otherwise index above
                        MM = Impact marker life
                        B  = Buoyancy * 10 (9 represents 10)
                        SS = Speed, m/sec
                */

                time_to_live = CMM % 100;
                colour = (CMM / 100) % 10;
                impactMarkerLife = (CMM / 1000) % 100;
                integer buo = (CMM / 100000) % 10;
                if (buo == 9) {
                    buo = 10;
                }
                buoy = buo / 10.0;
                SPEED = (CMM / 1000000) % 100;

                /*  Encode the colour and time to live in the name
                    so a target we impact can use them for its
                    impact markers.  */
                string pname = llList2String(llGetPrimitiveParams(
                    [ PRIM_NAME ]), 0);
                pname = "CMM=" + (string) ((colour * 100) + impactMarkerLife) + ", " +
                //  Append initial position for range calculation
                        "P=" + (string) launchPos + ", " + pname;
                llSetLinkPrimitiveParamsFast(LINK_THIS,
                    [ PRIM_NAME, pname ]);

                llCollisionSound("", 1.0);          // Disable collision sounds
                llSetBuoyancy(buoy);                // Set buoyancy of object: 0 = fall, 1 = float

                rotation rot = llGetRot();
                vector vel = llRot2Fwd(rot);
                vel = vel * SPEED;                  // Multiply normalised vector by speed

                llSetStatus(STATUS_PHYSICS | STATUS_DIE_AT_EDGE, TRUE); // Make object obey physics
                llSetVelocity(vel, FALSE);
                llTargetOmega(tumbleAxis, tumbleRate, tumbleGain);  // Start object tumbling
                llSetTimerEvent(time_to_live);      // Set timed delete on non-collision
            }
        }

        //  Collision with an object or objects

        collision_start(integer total_number) {
            integer i;
            integer isTarget = FALSE;
            integer isAvatar = TRUE;
            key impactKey = NULL_KEY;

            /*  It is possible for more than one collision to be
                reported in a single collision event.  The
                parameters of individual collisions can be
                queried with the llDetected...() functions,
                all of which take an argument of collision
                number from 0 to total_number - 1 reported in
                the collision_start() event.

                In practice, I have rarely seen multiple collisions
                reported in one event, but it can happen in
                the case of coincident or near-coincident objects
                or due to imprecision in the simulator's physics
                engine.

                If you get multiple collisions, there's no obvious
                way to choose one as more "precise" based upon the
                information available from llDetected...().  You
                might think that llDetectedPos() would be useful,
                but it just gives you the position of the centre of
                mass of the object you hit, which may be far from the
                point of impact.

                Our approach for multiple collisions is as follows.
                We walk through the collisions looking for collisions
                with targets or avatars.  If we find one, we choose it,
                as it requires special handling and is more likely
                to be what the user was trying to hit as opposed to
                any other random object.  If none of the hits was a
                target or avatar, we just pick the last one in the
                list.

                Again, since multiple collisions are rare, this is
                something users will not frequently encounter.  */

            for (i = 0; i < total_number; i++) {
/* IF TRACE
                if (trace) {
                    llOwnerSay("Collision " + (string) (i + 1) + " of " +
                        (string) total_number + ": " + llDetectedName(i) +
                        " key " + (string) llDetectedKey(i));
                }
/* END TRACE */
                key what = llDetectedKey(i);    // With what did we collide ?
                if (what != owner) {
                    list objd = llGetObjectDetails(what, [ OBJECT_DESC, OBJECT_CREATION_TIME ]);
                    isTarget = isTarget || (llList2String(objd, 0) == targetDesc);
                    impactKey = what;               // Yes.  Remember key
                    /*  To distinguish between avatars and other objects, we use
                        the detail that avatars report a null string for creation
                        time, while all other objects return a time stamp.  */
                    if (llList2String(objd, 1) != "") { // Is this not an avatar ?
                        isAvatar = FALSE;
                    }
                    //  If it's a target, choose this collision
                    if (isTarget) {
                        i = total_number;
                    }
                }
            }

            if (impactKey != NULL_KEY) {

                /*  If we have already hit the ground, only process the
                    impact if it's with a target or avatar.  This avoids
                    embarrassing double impacts due to imprecision in
                    Second Life's collision detection, while still
                    performing actions which are relevant to impacts
                    that do not place impact markers.  */
                if ((!hitGround) || isTarget || isAvatar) {
                    impact(isTarget, isAvatar, impactKey);
                }
/* IF TRACE
                else {
                    if (trace) {
                        llOwnerSay("    Ignored object collision after ground collision.");
                    }
                }
/* END TRACE */
                impacted = TRUE;
            }
/* IF TRACE
              else if (trace) {
                llOwnerSay("Ignored collision with myself.");
            }
/* END TRACE */
        }

        //  Collision with the ground

        land_collision_start(vector pos) {
/* IF TRACE
            if (trace) {
                llOwnerSay("Land collision at " + (string) pos);
            }
/* END TRACE */
            hitGround = TRUE;
            /*  When we impact an object near ground level, the
                imprecision of the Second Life geometry engine
                and bounding boxes will sometimes give us both
                a collision with the object and a
                land_collision_start().  If we've already seen
                the object collision, set impacted, and are
                waiting to die, don't report the extra land
                collision.  However, if we see the land collision
                first, still allow object collisions to be
                reported, as we may want them to act upon
                targets or avatars.  */
            if (!impacted) {
                impact(FALSE, FALSE, NULL_KEY);
            }
/* IF TRACE
              else {
                if (trace) {
                    llOwnerSay("Ignoring land collision after object collision.");
                }
            }
/* END TRACE */
        }

        /*  The timer is used to get rid of projectiles which don't
            collide with anything during their specified lifetime.  It
            is also used to delete the projectile after a collision.  */

        timer() {
            llDie();
        }
    }
