with AUnit;
with AUnit.Test_Cases;

package Command_Line_Tests is

   type Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Command line"));

   overriding
   procedure Register_Tests (T : in out Test);

   --  Every test starts with a scratch directory holding only the picture.
   overriding
   procedure Set_Up (T : in out Test);

end Command_Line_Tests;
