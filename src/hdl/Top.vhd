------------------------------------------------------------------------------------------------------------------------------------------------------
-- Engineer: Naomi Gonzalez
--
-- Description: Full Self Trigger 
------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

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

        slip_i          : in  integer_vector(NUM_ETROCS - 1 downto 0);
        rate_i          : in  integer range 0 to 2; -- 0==320, 1==640, 2==1280

        active_o        : out std_logic_vector(NUM_ETROCS - 1 downto 0);  -- '1' when the flashing bit is being cleared
        trigger_o       : out std_logic;
        cnts_o          : out integer_vector(NUM_ETROCS - 1 downto 0)
    );
end self_trig;

architecture Behavioral of self_trig is


    type data_flash_array_t is array (integer range 0 to 2) of std_logic_vector(UPLINK_WIDTH - 1 downto 0);
    signal data_flash_320_640_1280 : data_flash_array_t;

    signal flash_active_0 : std_logic_vector(224/8 - 1 downto 0);  -- 28 bits for rate 0
    signal flash_active_1 : std_logic_vector(224/16 - 1 downto 0); -- 14 bits for rate 1
    signal flash_active_2 : std_logic_vector(224/32 - 1 downto 0); -- 7 bits for rate 2

begin

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
                flash_inst_0 : entity work.FlashBitClear
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
                flash_inst_1 : entity work.FlashBitClear
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
                flash_inst_2 : entity work.FlashBitClear
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
                flash_active_1 & (others => '0') when rate_i = 1 else
                flash_active_2 & (others => '0');

    --------------------------------------------------------------------------------
    -- Connect to Trigger Generator
    --------------------------------------------------------------------------------
    trigger_inst : entity work.trigger_rx
        generic map (
            DATA_WIDTH => NUM_ETROCS,
            CNT_BITS   => CNT_BITS,
            WIDTH      => UPLINK_WIDTH
        )
        port map (
            clock         => clk_i,
            reset         => reset_i,
            uplink_data_i => data_flash_320_640_1280(rate_i),
            enable_i      => enable_i,
            slip_i        => slip_i,
            rate_i        => rate_i,
            trigger_o     => trigger_o,
            cnts_o        => cnts_o
        );
end Behavioral;







