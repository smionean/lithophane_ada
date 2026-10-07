------------------------------------------------------------------------------
--  stl_tests.ads
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;

package STL_Tests is

   type Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("STL output"));

   overriding
   procedure Register_Tests (T : in out Test);

end STL_Tests;
