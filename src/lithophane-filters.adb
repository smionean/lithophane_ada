------------------------------------------------------------------------------
--  lithophane-filters.adb
--
--  Body of Lithophane.Filters. The Bartlett, Gauss and Square builders
--  currently return all-zero (identity) kernels; only Sharpen carries real
--  weights (-1 everywhere, centre chosen so the weights sum to 1).
--  Apply_On_Point does an edge-extended convolution normalised by the
--  kernel weight sum and clamped to Color_Type; a null kernel leaves the
--  point untouched. Apply_Filter runs it over the whole image from a copy
--  of the source. Apply_Threshold_Filter drops sub-threshold pixels to 0.
--
--  Created : 2026-08-23
--  Author  : Simon Beàn
------------------------------------------------------------------------------

package body Lithophane.Filters is

   function Create_Bartlett_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   is
      a_filter : constant Matrix_Filter_Type (1 .. X, 1 .. Y) :=
        [for J in 1 .. X => [for K in 1 .. Y => 0]];
   begin
      return a_filter;
   end Create_Bartlett_Filter;

   function Create_Gauss_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   is
      a_filter : constant Matrix_Filter_Type (1 .. X, 1 .. Y) :=
        [for J in 1 .. X => [for K in 1 .. Y => 0]];
   begin
      return a_filter;
   end Create_Gauss_Filter;

   function Create_Square_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   is
      a_filter : constant Matrix_Filter_Type (1 .. X, 1 .. Y) :=
        [for J in 1 .. X => [for K in 1 .. Y => 0]];
   begin
      return a_filter;
   end Create_Square_Filter;

   function Create_Sharpen_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   is
      mid_c    : constant Integer := (1 + X) / 2;
      mid_l    : constant Integer := (1 + Y) / 2;
      a_filter : Matrix_Filter_Type (1 .. X, 1 .. Y) :=
        [for J in 1 .. X => [for K in 1 .. Y => -1]];
   begin
      --  Every weight is -1 except the centre, chosen so that the weights
      --  sum to 1: the output keeps the image's brightness while boosting
      --  the difference between a pixel and its neighbourhood.
      a_filter (mid_c, mid_l) := X * Y;
      return a_filter;
   end Create_Sharpen_Filter;

   function Apply_On_Point
     (the_image  : Matrix_Type;
      pos_c      : Natural;
      pos_l      : Natural;
      the_filter : Matrix_Filter_Type) return Color_Type
   is
      dimension  : constant Integer := the_filter'Length (1);
      milieu     : constant Integer := dimension / 2;

      first_c    : constant Integer := the_image'First (1);
      last_c     : constant Integer := the_image'Last (1);
      first_l    : constant Integer := the_image'First (2);
      last_l     : constant Integer := the_image'Last (2);

      somme      : Integer := 0;
      filter_sum : Integer := 0;
      src_c      : Integer;
      src_l      : Integer;
      result     : Integer;
   begin
      for i in the_filter'Range (1) loop
         for j in the_filter'Range (2) loop
            --  Position in the image covered by the filter cell (i, j),
            --  the filter being centred on (pos_c, pos_l).
            src_c := pos_c - milieu + (i - the_filter'First (1));
            src_l := pos_l - milieu + (j - the_filter'First (2));

            --  Clamp to the edges of the image (edge extension).
            if src_c < first_c then
               src_c := first_c;
            elsif src_c > last_c then
               src_c := last_c;
            end if;

            if src_l < first_l then
               src_l := first_l;
            elsif src_l > last_l then
               src_l := last_l;
            end if;

            somme :=
              somme
              + the_filter (i, j) * Integer (the_image (src_c, src_l));
            filter_sum := filter_sum + the_filter (i, j);
         end loop;
      end loop;

      --  A null filter leaves the point untouched.
      if filter_sum = 0 then
         return the_image (pos_c, pos_l);
      end if;

      result :=
        Integer (Float'Rounding (Float (somme) / Float (filter_sum)));

      --  Clamp the result to the valid colour range.
      if result < Integer (Color_Type'First) then
         result := Integer (Color_Type'First);
      elsif result > Integer (Color_Type'Last) then
         result := Integer (Color_Type'Last);
      end if;

      return Color_Type (result);
   end Apply_On_Point;

   procedure Apply_Filter
     (the_image : Matrix_Access; the_filter : Matrix_Filter_Type)
   is
      --  Work from a copy so that every point is filtered from the original
      --  image and not from neighbours that have already been rewritten.
      source : constant Matrix_Type := the_image.all;
   begin
      for c in the_image.all'Range (1) loop
         for l in the_image.all'Range (2) loop
            the_image.all (c, l) :=
              Apply_On_Point (source, c, l, the_filter);
         end loop;
      end loop;
   end Apply_Filter;

   procedure Apply_Threshold_Filter
     (the_image : Matrix_Access; the_threshold : Color_Type) is
   begin
      for c in 1 .. the_image.all'Last (1) loop
         for l in 1 .. the_image.all'Last (2) loop
            if the_image.all (c, l) < the_threshold then
               the_image.all (c, l) := Color_Type'First;
            else
               the_image.all (c, l) := the_image.all (c, l);
            end if;

         end loop;
      end loop;

   end Apply_Threshold_Filter;

end Lithophane.Filters;
