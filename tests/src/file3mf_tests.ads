with AUnit;
with AUnit.Test_Cases;

package File3mf_Tests is

   type Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("3MF output"));

   overriding
   procedure Register_Tests (T : in out Test);

end File3mf_Tests;
