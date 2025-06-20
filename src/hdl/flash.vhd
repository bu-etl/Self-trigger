------------------------------------------------------------------------------------------------------------------------------------------------------
-- Engineer: Naomi Gonzalez
--
-- Description: Detect ETROC Flashing Bit and Clear it
-- The flashing bit pattern toggles from 1 -> 0 -> 1 -> 0 every 3546 clock cycles
------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity flash_bit is
  generic (
    DATA_WIDTH   : integer := 8;    
    FLASH_PERIOD : integer := 3546; -- Clock cycles between flashing bit pattern
    THRESHOLD    : integer := 7    -- Threshold 
  );
  port (
    clk_i    : in  std_logic;
    reset_i  : in  std_logic;
    data_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    data_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
    active_o : out std_logic  -- '1' when the flashing bit is cleared, '0' when searching
  );
end flash_bit;

architecture Behavioral of flash_bit is

  type state_type is (INIT, SEARCH, ACTIVE);
  signal state : state_type := INIT;

  signal clk_counter : integer range 0 to FLASH_PERIOD*2-1 := 0;
  signal index       : integer range 0 to DATA_WIDTH-1 := 0;
  signal count       : integer range 0 to THRESHOLD := 0;
  
  signal active_o_internal : std_logic := '0';

begin

  active_o <= active_o_internal;

  process(clk_i)
    variable tmp_data : std_logic_vector(DATA_WIDTH-1 downto 0);
    variable found : boolean;
  begin
    if rising_edge(clk_i) then
      if reset_i = '1' then
        clk_counter <= 0;
        index       <= 0;
        state       <= INIT;
        active_o_internal <= '0';
        count       <= 0; 
        data_o      <= (others => '0'); 
      else 

        case state is 
          
          when INIT =>

            data_o <= data_i;
            active_o_internal <= '0';
            found := false;

            -- Look for first '1' bit in data word starting at index
            for i in index to DATA_WIDTH-1 loop
              if data_i(i) = '1' and not found then
                index <= i;
                state <= SEARCH;
                clk_counter <= 0;
                count <= 0;
                found := true;
              end if;
            end loop;

            -- Check rest of data word if still no '1' bit is found
            if not found then
              for i in 0 to index-1 loop
                if data_i(i) = '1' and not found then
                  index <= i;
                  state <= SEARCH;
                  clk_counter <= 0;
                  count <= 0;
                  found := true;
                end if;
              end loop;
            end if;

          when SEARCH =>

            data_o <= data_i;
            active_o_internal <= '0';

            if clk_counter = FLASH_PERIOD*2 - 1 then
              -- Reset clock counter after 2 flash periods
              clk_counter <= 0;

              -- Increase count if pattern is observed 
              if data_i(index) = '1' then
                count <= count + 1;

                -- If pattern observed enough times move to ACTIVE state
                if count = THRESHOLD - 1 then
                  state <= ACTIVE;
                end if;

              -- If pattern not observed anymore revert to INIT state
              else
                state <= INIT;
                count <= 0;
                clk_counter <= 0;
              end if;

            else
              clk_counter <= clk_counter + 1;
            end if;

          when ACTIVE =>

            active_o_internal <= '1';
            tmp_data := data_i;

            if clk_counter = FLASH_PERIOD*2 - 1 then
              -- Reset clock counter after 2 flash periods
              clk_counter <= 0;

              -- Clear flashing bit if pattern continues 
              if data_i(index) = '1' then
                tmp_data(index) := '0';

              -- Revert to INIT state if patter not observed anymore
              else
                state <= INIT;
                count <= 0;
                clk_counter <= 0;
              end if;

            else
              clk_counter <= clk_counter + 1;
            end if;

           data_o <= tmp_data;

        end case; 

      end if; 
    end if; 
  end process;  
end Behavioral;

