------------------------------------------------------------------------------------------------------------------------------------------------------
-- Engineer: Naomi Gonzalez
--
-- Description: Full Self Trigger 
------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_MISC.all;

use work.def_pkg.all;

entity self_trig is 
    generic (
        -- trigger_rx
        NUM_ETROCS      : integer := 28;
        CNT_BITS        : integer := 26;
        UPLINK_WIDTH    : integer := 224;

        -- flash 
        FLASH_PERIOD    : integer := 3546; 
        THRESHOLD       : integer := 10
    );
    port (
        clk_i           : in  std_logic;
        reset_i         : in  std_logic;
        uplink_data_i   : in  std_logic_vector(UPLINK_WIDTH - 1 downto 0);
        enable_i        : in  std_logic_vector(UPLINK_WIDTH - 1 downto 0);

        --slip_i          : in  integer_vector(NUM_ETROCS - 1 downto 0);
        slip_i          : in  std_logic_vector(NUM_ETROCS * INTEGER_WIDTH - 1 downto 0);
        rate_i          : in  integer range 0 to 2; -- 0==320, 1==640, 2==1280

        active_o        : out std_logic_vector(NUM_ETROCS - 1 downto 0);  -- '1' when the flashing bit is being cleared
        trigger_o       : out std_logic;
        --cnts_o          : out integer_vector(NUM_ETROCS - 1 downto 0)
        cnts_o          : out std_logic_vector(NUM_ETROCS * INTEGER_WIDTH - 1 downto 0)
    );
end self_trig;

architecture Behavioral of self_trig is

    signal slip_i_internal : integer_vector(NUM_ETROCS - 1 downto 0);

    type data_flash_array_t is array (integer range 0 to 2) of std_logic_vector(UPLINK_WIDTH - 1 downto 0);
    signal data_flash_320_640_1280 : data_flash_array_t;

    signal flash_active_0 : std_logic_vector(UPLINK_WIDTH/8 - 1 downto 0);   -- 28 bits for rate 0 (320)
    signal flash_active_1 : std_logic_vector(UPLINK_WIDTH/16 - 1 downto 0); -- 14 bits for rate 1 (640)
    signal flash_active_2 : std_logic_vector(UPLINK_WIDTH/32 - 1 downto 0); -- 7 bits for rate 2 (1280)

    signal active_enable : std_logic_vector(UPLINK_WIDTH - 1 downto 0);
    signal trigger_uplink_data : std_logic_vector(UPLINK_WIDTH - 1 downto 0);
    signal trigger_enable      : std_logic_vector(UPLINK_WIDTH - 1 downto 0);

begin
    
    -- Convert into an array of integers
    convert_slip_i : for i in 0 to NUM_ETROCS - 1 generate
        slip_i_internal(i) <= to_integer(unsigned(slip_i((i+1) * INTEGER_WIDTH - 1 downto i * INTEGER_WIDTH)));
    end generate;
    
    flash_irate_gen : for IRATE in 0 to 2 generate
        constant ETROC_WIDTH : integer := 2 ** (IRATE + 3); -- 8, 16, or 32
        
        constant NUM_LINKS_PER_RATE : integer := UPLINK_WIDTH / ETROC_WIDTH;
    begin

    --------------------------------------------------------------------------------
    -- Generate Flashing Bit Detector for each ETROC at each Data Rate
    --------------------------------------------------------------------------------
        flash_ietroc_gen : for IETROC in 0 to NUM_LINKS_PER_RATE - 1 generate
        begin

            gen_rate_0 : if IRATE = 0 generate
                flash_inst_0 : entity work.flash_bit
                    generic map (
                        DATA_WIDTH      => ETROC_WIDTH,
                        FLASH_PERIOD    => FLASH_PERIOD,
                        THRESHOLD       => THRESHOLD
                    )
                    port map (
                        clk_i       => clk_i,
                        reset_i     => reset_i,
                        data_i      => uplink_data_i((IETROC + 1) * ETROC_WIDTH - 1 downto IETROC * ETROC_WIDTH),
                        data_o      => data_flash_320_640_1280(IRATE)((IETROC + 1) * ETROC_WIDTH - 1 downto IETROC * ETROC_WIDTH),
                        active_o    => flash_active_0(IETROC)
                    );
            end generate gen_rate_0;
            
            gen_rate_1 : if IRATE = 1 generate
                flash_inst_1 : entity work.flash_bit
                    generic map (
                        DATA_WIDTH      => ETROC_WIDTH,
                        FLASH_PERIOD    => FLASH_PERIOD,
                        THRESHOLD       => THRESHOLD
                    )
                    port map (
                        clk_i       => clk_i,
                        reset_i     => reset_i,
                        data_i      => uplink_data_i((IETROC + 1) * ETROC_WIDTH - 1 downto IETROC * ETROC_WIDTH),
                        data_o      => data_flash_320_640_1280(IRATE)((IETROC + 1) * ETROC_WIDTH - 1 downto IETROC * ETROC_WIDTH),
                        active_o    => flash_active_1(IETROC)
                    );
            end generate gen_rate_1;
            
            gen_rate_2 : if IRATE = 2 generate
                flash_inst_2 : entity work.flash_bit
                    generic map (
                        DATA_WIDTH      => ETROC_WIDTH,
                        FLASH_PERIOD    => FLASH_PERIOD,
                        THRESHOLD       => THRESHOLD
                    )
                    port map (
                        clk_i       => clk_i,
                        reset_i     => reset_i,
                        data_i      => uplink_data_i((IETROC + 1) * ETROC_WIDTH - 1 downto IETROC * ETROC_WIDTH),
                        data_o      => data_flash_320_640_1280(IRATE)((IETROC + 1) * ETROC_WIDTH - 1 downto IETROC * ETROC_WIDTH),
                        active_o    => flash_active_2(IETROC)
                    );
            end generate gen_rate_2;

        end generate flash_ietroc_gen;
    end generate flash_irate_gen;

    -- Assign the active_o port based on rate_i. Smaller vectors for rates 1 and 2 are padded with '0'.
    active_o <= flash_active_0 when rate_i = 0 else
                flash_active_1 & std_logic_vector(to_unsigned(0, NUM_ETROCS - flash_active_1'length)) when rate_i = 1 else
                flash_active_2 & std_logic_vector(to_unsigned(0, NUM_ETROCS - flash_active_2'length));

    -- Create enable mask based on when the flashing bit is being cleared 
    process (rate_i, flash_active_0, flash_active_1, flash_active_2)
    begin 
        case rate_i is
            when 0 => -- For each bit in flash_active_0, copy that bit 8 times 
                for i in 0 to flash_active_0'length - 1 loop
                    active_enable((i + 1) * 8 - 1 downto i * 8) <= (others => flash_active_0(i));
                end loop;
            when 1 => -- For each bit in flash_active_1, copy that bit 16 times 
                for i in 0 to flash_active_1'length - 1 loop
                    active_enable((i + 1) * 16 - 1 downto i * 16) <= (others => flash_active_1(i));
                end loop;
            when 2 => -- For each bit in flash_active_2, copy that bit 32 times
                for i in 0 to flash_active_2'length - 1 loop
                    active_enable((i + 1) * 32 - 1 downto i * 32) <= (others => flash_active_2(i));
                end loop;
            when others =>
                active_enable <= (others => '0');
        end case;
    end process;


    -- Process to create static signals 
    process(rate_i, data_flash_320_640_1280, enable_i, active_enable)
    begin
        trigger_uplink_data <= data_flash_320_640_1280(rate_i);
        trigger_enable <= enable_i and active_enable;
    end process;

    --------------------------------------------------------------------------------
    -- Connect to Trigger Generator
    --------------------------------------------------------------------------------
    trigger_inst : entity work.trigger_rx
        generic map (
            NUM_ETROCS => NUM_ETROCS,
            CNT_BITS   => CNT_BITS,
            WIDTH      => UPLINK_WIDTH
        )
        port map (
            clock         => clk_i,
            reset         => reset_i,
            uplink_data_i => trigger_uplink_data,
            enable_i      => trigger_enable,
            slip_i        => slip_i,
            rate_i        => rate_i,
            trigger_o     => trigger_o,
            cnts_o        => cnts_o
        );
end Behavioral;





