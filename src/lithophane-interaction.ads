package Lithophane.Interaction is

   --  Raised when an answer cannot be decoded or is not one of the proposed
   --  choices, or when the standard input ends before every question has
   --  been answered; the message of the exception says which.
   Interaction_Error : exception;

   --  Raised when the user answers 0 (exit program) to a menu.
   Interaction_Cancelled : exception;

   procedure Show_Interaction (Settings : in out Settings_Record);

end Lithophane.Interaction;
