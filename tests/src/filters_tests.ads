with AUnit;
with AUnit.Test_Cases;

package Filters_Tests is

   type Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Filters"));

   overriding
   procedure Register_Tests (T : in out Test);

end Filters_Tests;
