--------------------------------------------------------------------------------
-- Engineer: Naomi Gonzalez
--
-- Description: Shared package for repo simulation
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package def_pkg is

    constant INTEGER_WIDTH : integer := 8; -- Allows for values 0-255
    type integer_vector is array (integer range <>) of integer;

end package def_pkg;
