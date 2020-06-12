    /*
                      Fourmilab Target Marker

                           by John Walker

        Target markers are rezzed by the target script to
        indicate the location of impacts on the target.  A start
        parameter is passed whose decimal digits are interpreted
        as CMM, where C is a colour index (see below) and MM is
        the time in seconds before the marker will delete
        itself, with 0 indicating the marker is immortal.

    */

    integer colour;             // Colour index of marker

    /*  Standard colour names and RGB values.  The first 8
        colours have the indices of the classic AutoCAD
        colour palette.  */

    list colours = [
        "black", <0, 0, 0>,         // 0
        "red", <1, 0, 0>,           // 1
        "yellow", <1, 1, 0>,        // 2
        "green", <0, 1, 0>,         // 3
        "cyan", <0, 1, 1>,          // 4
        "blue", <0, 0, 1>,          // 5
        "magenta", <1, 0, 1>,       // 6
        "white", <1, 1, 1>,         // 7

        /*  We fill out 8 and 9, which are also white in the
            AutoCAD palette, with useful colours accessible
            with a single digit index.  These are defined
            as in HTML5.  */

        "orange", <1, 0.647, 0>,    // 8
        "grey", <0.5, 0.5, 0.5>     // 9
    ];

    default {

        state_entry() {
        }

        on_rez(integer start_param) {
            /*  Start param is encoded as follows:
                        CMM

                        MM = Time to live, 0 - 99 seconds (0 = immortal)
                        C  = Colour index, 0 = white, 7 = black, otherwise index above
            */
            if (start_param == 1000) {          // No CMM= in impactor's name
                start_param = 830;              // Colour orange, life 30 seconds
            }
            integer time_to_live = start_param % 100;
            colour = (start_param / 100) % 10;
            llSetLinkPrimitiveParamsFast(LINK_THIS,
                [ PRIM_COLOR, ALL_SIDES,
                    llList2Vector(colours, (colour * 2) + 1), 1 ]);

            if (start_param > 0) {
                llSetTimerEvent((float) time_to_live);   // Start self-deletion timer
            }
        }

        //  The timer event deletes target markers after the specified interval

        timer() {
            llDie();                    // I'm out of here
        }
    }
