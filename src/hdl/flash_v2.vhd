------------------------------------------------------------------------------------------------------------------------------------------------------
-- Engineer: Naomi Gonzalez
--
-- Description: Detect ETROC Flashing Bits Lock onto it and then Clear them
-- The flashing bit pattern toggles from 1 -> 0 -> 1 -> 0 every 3546 clock cycles
-- 
-- The pattern exists on all trigger bits selected based on trigger data size which is set
-- using the triggerGranularity register on the ETROC
-- (e.g triggerGranularity = 4 -> trigger data size is 8 and pattern = 0xff -> 0x0 -> 0xff -> 0x0 every 3546 clock cycles)
-- The pattern needs to be aligned to have all trigger bits flash in the window of the elink width 
-- (bitslip until pattern is found and lock onto it)
------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity flash_bit is
  generic (
    DATA_WIDTH   : integer := 8;    
    FLASH_PERIOD : integer := 3546; -- Clock cycles between flashing bit pattern
    THRESHOLD    : integer := 7    -- Threshold to lock
  );
  port (
    clk_i    : in  std_logic;
    reset_i  : in  std_logic;
    clear_i  : in  std_logic;

    data_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    data_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
    locked_o : out std_logic  -- '1' when the flashing bits are aligned, '0' otherwise
  );
end flash_bit;

architecture Behavioral of flash_bit is
  
  type state_type is (ALIGN, VERIFY, LOCKED);
  signal state : state_type := ALIGN;

  signal clk_counter : integer range 0 to FLASH_PERIOD*2-1 := 0;
  signal slip_count  : integer range 0 to DATA_WIDTH - 1 := 0;
  signal count       : integer range 0 to THRESHOLD := 0;

  signal data_sliped  : std_logic_vector(DATA_WIDTH-1 downto 0);
  constant ALL_ONES   : std_logic_vector(data_i'range) := (others => '1');
  constant ALL_ZEROS  : std_logic_vector(data_i'range) := (others => '0');

  signal expected_pattern : std_logic := '1';

begin

  --------------------------------------------------------------------------------
  -- Generate Bitslipper used for alignment 
  --------------------------------------------------------------------------------

  bitslip_inst : entity work.bitslip
    generic map (
      g_DATA_WIDTH            => DATA_WIDTH,
      g_SLIP_CNT_WIDTH        => DATA_WIDTH,
      g_TRANSMIT_LOW_TO_HIGH  => true -- TODO: check this
    )
    port map (
      clk_i       => clk_i;
      slip_cnt_i  => slip_count;
      data_i      => data_i;
      data_o      => data_sliped
    );


  process(clk_i)
    variable tmp_data : std_logic_vector(DATA_WIDTH-1 downto 0);
    variable pattern_correct : boolean;
  begin

    if rising_edge(clk_i) then


      -- Sync Reset
      if reset_i = '1' then
        state       <= ALIGN;
        clk_counter <= 0;
        slip_count  <= 0;
        count       <= 0;

        data_o   <= (others => '0');
        locked_o <= '0';
      else 

  --------------------------------------------------------------------------------
  -- Flashing Bit State Machine
  --------------------------------------------------------------------------------
        case state is 
          
          when ALIGN => 

            data_o    <= data_sliped;
            locked_o  <= '0';

            -- If flashing bits seen, move to VERIFY state 
            if data_sliped = ALL_ONES then
              expected_pattern <= '0';
              state            <= VERIFY;
              clk_counter      <= 0;
              count            <= 0;
            else
              if clk_counter = FLASH_PERIOD*2 -1 then
                clk_counter <= 0;

                -- bitslip by one if flashing period passed and flashing pattern not see
                if slip_count = DATA_WIDTH - 1 then
                  slip_count <= 0;
                else
                  slip_count <= slip_count + 1;
                end if;

              else
                clk_counter <= clk_counter + 1;
              end if;
            end if;


          when VERIFY =>

            data_o    <= data_sliped;
            locked_o  <= '0';

            pattern_correct :=  (expected_pattern = '1' and data_sliped = ALL_ONES) or
                                (expected_pattern = '0' and data_sliped = ALL_ZEROS);

            if clk_counter = FLASH_PERIOD - 1 then
              -- Reset clock counter after flash period
              clk_counter <= 0;

              -- Increase count if pattern is observed 
              if pattern_correct then
                count <= count + 1;
                expected_pattern <= not expected_pattern;

                -- If pattern observed enough times move to LOCKED state
                if count = THRESHOLD - 1 then
                  state <= LOCKED;
                end if;

              -- If pattern not observed anymore revert to ALIGN state
              else 
                state <= ALIGN;
                count <= 0;
                clk_counter <= 0;
              end if;

            else
              clk_counter <= clk_counter + 1;
            end if;


          when LOCKED =>

            locked_o <= '1';
            tmp_data := data_sliped;

            pattern_correct :=  (expected_pattern = '1' and data_sliped = ALL_ONES) or
                                (expected_pattern = '0' and data_sliped = ALL_ZEROS);

            if clk_counter = FLASH_PERIOD - 1 then
              -- Reset clock counter after a flash period
              clk_counter <= 0;

              -- Clear flashing bits if pattern continues 
              if pattern_correct then
                expected_pattern <= not expected_pattern;
                if clear_i then
                  tmp_data := (others => '0');
                end if;

              -- Revert to ALIGN state if pattern not observed anymore
              else
                state <= ALIGN;
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

