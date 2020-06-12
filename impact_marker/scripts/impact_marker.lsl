    /*
                      Fourmilab Impact Marker

                           by John Walker

        Projectiles place an impact marker at the location of
        impact (collision) with any object other than a
        Fourmilab target, which handles its own scoring of
        impacts.  Impact markers are five-pointed stars whose
        texture is white, but which can be coloured to indicate
        the thrower of the projectile.  When the projectile
        rezzes a target marker, it passes an integer start_param
        coded as CMM to the start_param() event of this object.
        This is used to set the colour C (see the table below)
        and time to live, MM, in seconds of the impact marker,
        with an MM value of zero indicating the target marker is
        immortal.

    */

    key owner;                  // UUID of owner
    integer colour;             // Colour index of marker

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

    default {

        state_entry() {
            owner = llGetOwner();
        }

        on_rez(integer start_param) {
            /*  The start_param is encoded as follows:
                        CMM

                        MM = Time to live, 0 - 99 seconds (0 = immortal)
                        C  = Colour index, 0 = white, 7 = black, otherwise index above
            */
            integer time_to_live = start_param % 100;
            colour = (start_param / 100) % 10;
            llSetLinkPrimitiveParamsFast(LINK_THIS,
                [ PRIM_COLOR, ALL_SIDES,
                    llList2Vector(colours, (colour * 2) + 1), 1 ]);

            if (start_param > 0) {
                llSetTimerEvent((float) time_to_live);   // Start self-deletion timer
            }
        }

        //  The timer event deletes impact markers after a decent interval

        timer() {
            llDie();                    // I'm out of here
        }
    }
