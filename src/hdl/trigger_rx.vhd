------------------------------------------------------------------------------------------------------------------------------------------------------
-- Engineer: Naomi Gonzalez
--
-- Description: Creates an L1A if detects hit on specfic ETROC data word
------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

use work.def_pkg.all;

entity trigger_rx is
  generic
  (
    NUM_ETROCS : integer := 28;
    CNT_BITS   : integer := 26;
    WIDTH      : integer := 224
  );
  port
  (
    clock         : in std_logic;
    reset         : in std_logic;
    uplink_data_i : in std_logic_vector (WIDTH - 1 downto 0);
    enable_i      : in std_logic_vector (WIDTH - 1 downto 0);

    --slip_i : in integer_vector (NUM_ETROCS - 1 downto 0);
    slip_i : in  std_logic_vector(NUM_ETROCS * INTEGER_WIDTH - 1 downto 0);
    rate_i : in integer range 0 to 2; -- 0==320, 1==640, 2==1280

    trigger_o : out std_logic;

    --cnts_o : out integer_vector (NUM_ETROCS - 1 downto 0)
    cnts_o : out std_logic_vector(NUM_ETROCS * INTEGER_WIDTH - 1 downto 0)
  );
end trigger_rx;

architecture rtl of trigger_rx is

  signal slip_i_internal : integer_vector(NUM_ETROCS - 1 downto 0);
  signal cnts_o_internal : std_logic_vector(NUM_ETROCS * INTEGER_WIDTH - 1 downto 0);

  type data_slip_array_t is array (integer range 2 downto 0) of std_logic_vector(WIDTH - 1 downto 0);
  signal data_slip_320_640_1280 : data_slip_array_t;

  signal data_slip   : std_logic_vector (WIDTH - 1 downto 0) := (others => '0');
  signal data_masked : std_logic_vector (WIDTH - 1 downto 0) := (others => '0');

  signal or_8, or_8_r, or_8_rr : std_logic_vector (NUM_ETROCS - 1 downto 0)   := (others => '0');
  signal or_16, or_16_r        : std_logic_vector (NUM_ETROCS/2 - 1 downto 0) := (others => '0');
  signal or_32                 : std_logic_vector (NUM_ETROCS/4 - 1 downto 0) := (others => '0');

  signal counter_reset : std_logic;

  attribute MARK_DEBUG                : string;
  attribute MARK_DEBUG of or_8        : signal is "true";
  attribute MARK_DEBUG of or_16       : signal is "true";
  attribute MARK_DEBUG of or_32       : signal is "true";
  attribute MARK_DEBUG of data_slip   : signal is "true";
  attribute MARK_DEBUG of data_masked : signal is "true";

begin

  -- Convert into an array of integers
  convert_slip_i : for i in 0 to NUM_ETROCS - 1 generate
    slip_i_internal(i) <= to_integer(unsigned(slip_i((i+1) * INTEGER_WIDTH - 1 downto i * INTEGER_WIDTH)));
  end generate;

  cnts_o <= cnts_o_internal;

  --------------------------------------------------------------------------------
  -- Generate Bitslippers for Each Data Rate
  --------------------------------------------------------------------------------

  slip_irate_gen : for IRATE in 0 to 2 generate
    constant NUM : integer := 2 ** (IRATE + 3);
  begin

    slip_ietroc_gen : for IETROC in 0 to 224/NUM - 1 generate
    begin

      bitslip_inst : entity work.bitslip
        generic
        map (
        g_DATA_WIDTH           => NUM,
        g_SLIP_CNT_WIDTH       => 5,
        g_TRANSMIT_LOW_TO_HIGH => true) -- TODO: check this
        port map
        (
          clk_i      => clock,
          slip_cnt_i => slip_i_internal(IETROC),
          data_i     => uplink_data_i((IETROC+1) * NUM - 1 downto IETROC*NUM),
          data_o     => data_slip_320_640_1280(IRATE)((IETROC + 1) * NUM - 1 downto IETROC * NUM)
        );

    end generate;
  end generate;

  -- multiplex the 3 different slippers into one signal
  process (clock) is
  begin
    if (rising_edge(clock)) then
      data_slip <= data_slip_320_640_1280(rate_i);
    end if;
  end process;

  --------------------------------------------------------------------------------
  -- Apply Enable Mask
  --------------------------------------------------------------------------------

  process (clock) is
  begin
    if (rising_edge(clock)) then
      data_masked <= data_slip and enable_i;
    end if;
  end process;

  --------------------------------------------------------------------------------
  -- OR Reduction
  --------------------------------------------------------------------------------

  process (clock) is
  begin
    if (rising_edge(clock)) then

      for I in or_8'range loop
        or_8(I) <= or_reduce(data_masked((I + 1) * 8 - 1 downto I * 8));
      end loop;

      for I in or_16'range loop
        or_16(I) <= or_reduce(or_8((I + 1) * 2 - 1 downto I * 2));
      end loop;

      for I in or_32'range loop
        or_32(I) <= or_reduce(or_16((I + 1) * 2 - 1 downto I * 2));
      end loop;

      -- delay the 8 and 16 bit reductions to align in time with the 32 bit reduction
      or_8_r  <= or_8;
      or_8_rr <= or_8_r;
      or_16_r <= or_16;

    end if;
  end process;

  --------------------------------------------------------------------------------
  -- Counters
  --------------------------------------------------------------------------------

  cnt_gen : for I in 0 to NUM_ETROCS - 1 generate
    -- rate=0 320  Mbps 0,1,2,3,4...27
    -- rate=1 640  Mbps 0,2,4,6,8,10,12,....
    -- rate=2 1280 Mbps 0,4,8,12,16,20,24

    signal enable   : std_logic                                := '0';
    signal cnt_flag : std_logic                                := '0';
    signal cnt      : std_logic_vector (CNT_BITS - 1 downto 0) := (others => '0');

  begin

    process (clock) is
    begin
      if (rising_edge(clock)) then

        case rate_i is

          when 0 =>
            enable   <= '1';
            cnt_flag <= or_8_rr(I);

          when 1 =>
            if (I mod 2 = 0) then
              enable   <= '1';
              cnt_flag <= or_16_r(I/2);
            else
              enable   <= '0';
              cnt_flag <= '0';
            end if;

          when 2 =>
            if (I mod 4 = 0) then
              enable   <= '1';
              cnt_flag <= or_32(I/4);
            else
              enable   <= '0';
              cnt_flag <= '0';
            end if;

          when others =>
            enable   <= '0';
            cnt_flag <= '0';

        end case;

      end if;
    end process;

    -- Process to create static signal
    process(reset, enable)
    begin
      counter_reset <= reset or not enable;
    end process;


    trig_rate_counter_inst : entity work.rate_counter
      generic
      map (
      g_CLK_FREQUENCY => x"02638e98",
      g_COUNTER_WIDTH => CNT_BITS)
      port
      map (
      clk_i   => clock,
      reset_i => counter_reset,
      en_i    => cnt_flag,
      rate_o  => cnt);

    cnts_o_internal((I+1) * INTEGER_WIDTH - 1 downto I * INTEGER_WIDTH) <= cnt(INTEGER_WIDTH - 1 downto 0);

  end generate;

  --------------------------------------------------------------------------------
  -- Trigger Output
  --------------------------------------------------------------------------------

  process (clock) is
  begin
    if (rising_edge(clock)) then
      trigger_o <= or_reduce(or_32);
    end if;
  end process;

end rtl;
