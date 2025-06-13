------------------------------------------------------------------------------------------------------------------------------------------------------
-- Engineer: Naomi Gonzalez
--
-- Description: Detect ETROC Flashing Bit and Clear it
------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity flash_bit is
  generic (
    DATA_WIDTH   : integer := 8;    
    FLASH_PERIOD : integer := 3546; -- Clock cycles between flashing bit pattern
    THRESHOLD    : integer := 10    -- Threshold 
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

  signal clk_counter : integer range 0 to FLASH_PERIOD-1 := 0;
  signal index       : integer range 0 to DATA_WIDTH-1 := 0;
  signal last_value  : std_logic_vector(FLASH_PERIOD-1 downto 0) := (others => '0'); 
  signal valid       : std_logic_vector(FLASH_PERIOD-1 downto 0) := (others => '1');
  signal num_valid   : integer range 0 to FLASH_PERIOD := FLASH_PERIOD;
  signal count       : integer range 0 to THRESHOLD := 0;
  
  signal active_o_internal : std_logic := '0';

begin

  active_o <= active_o_internal;

  process(clk_i)
    variable tmp : std_logic_vector(DATA_WIDTH-1 downto 0);
  begin
    if rising_edge(clk_i) then
      if reset_i = '1' then
        clk_counter <= 0;
        index       <= 0;
        last_value  <= (others => '0'); 
        valid       <= (others => '1');
        num_valid   <= FLASH_PERIOD;
        state       <= INIT;
        active_o_internal <= '0';
        count       <= 0; 
        data_o      <= (others => '0'); 
      else 

        -- Increase clock count 
        if clk_counter /= FLASH_PERIOD - 1 then
          clk_counter <= clk_counter + 1;
        else
          clk_counter <= 0;
        end if;

        case state is 
          
          when INIT =>
            active_o_internal <= '0';
            -- Move to SEARCH state once one flash period is done
            if clk_counter = FLASH_PERIOD - 1 then 
              state <= SEARCH;

            -- If first flash period save data value for each clock phase
            else 
              last_value(clk_counter) <= data_i(index); 
            end if;
            data_o <= data_i;

          when SEARCH =>
            active_o_internal <= '0';

            -- Check if value toggled
            if (valid(clk_counter) = '1') and (data_i(index) /= last_value(clk_counter)) then
              last_value(clk_counter) <= data_i(index);

              -- Increase threshold count if only valid phase left
              if num_valid = 1 then
                if count >= THRESHOLD then
                  state <= ACTIVE;
                else 
                  count <= count + 1;
                end if;
              end if;

            -- If value did not toggle remove from the search
            else 
                if (valid(clk_counter) = '1') and (data_i(index) = last_value(clk_counter)) then
                    valid(clk_counter) <= '0';
                    num_valid <= num_valid - 1;
                    count <= 0; 
                end if;
            end if;

            -- If no more valid phases, restart and move to next index
            if num_valid = 0 then
              if index = DATA_WIDTH - 1 then
                index <= 0;
              else
                index <= index + 1;
              end if;
              valid       <= (others => '1');
              last_value  <= (others => '0'); 
              state       <= INIT;
              num_valid   <= FLASH_PERIOD;
              count       <= 0; 
            end if;
            data_o <= data_i;

          when ACTIVE =>
            active_o_internal <= '1';
            tmp := data_i;

            -- Check that flashing bit pattern continues to happen
            if (valid(clk_counter) = '1') and (data_i(index) /= last_value(clk_counter)) then
              -- Update last value and clear flashing bit
              last_value(clk_counter) <= data_i(index);
              tmp(index) := '0';
            end if;
            data_o <= tmp;

        end case; 
      end if; 
    end if; 
  end process;  
end Behavioral;

