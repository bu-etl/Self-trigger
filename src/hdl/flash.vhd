------------------------------------------------------------------------------------------------------------------------------------------------------
-- Company: TAMU
-- Engineer: Naomi Gonzalez
--
-- Description: Detect ETROC Flashing Bit and Clear it
------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity FlashBitClear is
  generic (
    DATA_WIDTH   : integer := 8;   
    FLASH_PERIOD : integer := 3546; -- Clock cycles between flashing bit pattern
    THRESHOLD    : integer := 31    -- Threshold 
  );
  port (
    clk_i     : in  std_logic;
    reset_i   : in  std_logic;
    data_i    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    data_o    : out std_logic_vector(DATA_WIDTH-1 downto 0);
    active_o  : out std_logic  -- '1' when the flashing bit is cleared, '0' when searching
  );
end FlashBitClear;

architecture Behavioral of FlashBitClear is

  type state_type is (SEARCH, ACTIVE);
  signal state : state_type := SEARCH;


  signal period_counter : integer range 0 to FLASH_PERIOD-1 := 0;
  signal index : integer range 0 to DATA_WIDTH-1 := 0;
  signal index_init : std_logic := '0';
  signal last_value : std_logic := '0';
  signal index_count : integer range 0 to THRESHOLD := 0;

begin

  ----------------------------------------------------------------------
  -- State Process:  
  -- On every FLASH_PERIOD clock cycles check value of the index bit
  -- In SEARCH mode: 
  ---     if toggle observed: increase index_count until THRESHOLD is reached
  ---     else: cycle to a new index 
  -- In ACTIVE mode: 
  ---     if toggle is missed: revert to SEARCH mode
  ----------------------------------------------------------------------
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if reset_i = '1' then
        period_counter <= 0;
        index          <= 0;
        index_init     <= '0';
        last_value     <= '0';
        index_count    <= 0;
        state          <= SEARCH;
      else
        -- Increase period count until one flash period is reached
        if period_counter /= FLASH_PERIOD - 1 then
          period_counter <= period_counter + 1;

        -- Once a period cycle is complete reset period count and check index value
        else
          period_counter <= 0;

          case state is
            when SEARCH =>

               -- If first sample for this index: store its value and mark as initialized
              if index_init = '0' then
                last_value  <= data_i(index);
                index_init  <= '1';
                index_count <= 0;
              else
                -- Toggle observed: increase count store and store value
                if data_i(index) /= last_value then
                  index_count <= index_count + 1;
                  last_value  <= data_i(index);
                else
                  -- Toggle not observed: move to the next index and reinitialize
                  if index = DATA_WIDTH - 1 then
                    index <= 0;
                  else
                    index <= index + 1;
                  end if;
                  index_init  <= '0';
                  index_count <= 0;
                end if;
              end if;

              if index_count >= THRESHOLD then
                state <= ACTIVE;
              end if;
              
            when ACTIVE =>
              -- If first sample for this index: store its value and mark as initialized
              if index_init = '0' then
                last_value <= data_i(index);
                index_init <= '1';
              else
                -- Toggle found: update last_value
                if data_i(index) /= last_value then
                  last_value <= data_i(index);

                -- Toggle not found: revert back to SEARCH
                else
                  state       <= SEARCH;
                  index_init  <= '0';
                  index_count <= 0;

                  -- Move to next index to continure search
                  if index = DATA_WIDTH - 1 then
                    index <= 0;
                  else
                    index <= index + 1;
                  end if;

                end if;
              end if;
          end case;

        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------
  -- Output Process:  
  -- When in ACTIVE state, clear the flashing bit.
  ----------------------------------------------------------------------
  process(data_i, state, index)
    variable tmp : std_logic_vector(DATA_WIDTH-1 downto 0);
  begin
    tmp := data_i;
    if state = ACTIVE then
      tmp(index) := '0';
    end if;
    data_o <= tmp;
  end process;
  
  -- The active signal is '1' when in ACTIVE state, else '0'.
  active_o <= '1' when state = ACTIVE else '0';

end Behavioral;

