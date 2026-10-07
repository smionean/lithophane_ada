------------------------------------------------------------------------------
--  image_utilities_tests.ads
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;

package Image_Utilities_Tests is

   type Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Image utilities"));

   overriding
   procedure Register_Tests (T : in out Test);

end Image_Utilities_Tests;
