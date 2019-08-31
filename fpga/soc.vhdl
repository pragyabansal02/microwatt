library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

library work;
use work.wishbone_types.all;


-- 0x00000000: Main memory (1 MB)
-- 0xc0002000: UART0 (for host communication)
entity soc is
    generic (
	MEMORY_SIZE   : positive;
	RAM_INIT_FILE : string;
	RESET_LOW     : boolean
	);
    port(
	rst          : in  std_ulogic;
	system_clk   : in  std_logic;

	-- UART0 signals:
	uart0_txd    : out std_logic;
	uart0_rxd    : in  std_logic
	);
end entity soc;

architecture behaviour of soc is

    -- Wishbone master signals:
    signal wishbone_proc_out: wishbone_master_out;
    signal wishbone_proc_in: wishbone_slave_out;
    signal wishbone_dcore_in : wishbone_slave_out;
    signal wishbone_dcore_out : wishbone_master_out;
    signal wishbone_icore_in : wishbone_slave_out;
    signal wishbone_icore_out : wishbone_master_out;

    -- Processor signals:
    signal processor_adr_out : std_logic_vector(63 downto 0);
    signal processor_sel_out : std_logic_vector(7 downto 0);
    signal processor_cyc_out : std_logic;
    signal processor_stb_out : std_logic;
    signal processor_we_out  : std_logic;
    signal processor_dat_out : std_logic_vector(63 downto 0);
    signal processor_dat_in  : std_logic_vector(63 downto 0);
    signal processor_ack_in  : std_logic;

    -- UART0 signals:
    signal uart0_adr_in  : std_logic_vector(11 downto 0);
    signal uart0_dat_in  : std_logic_vector( 7 downto 0);
    signal uart0_dat_out : std_logic_vector( 7 downto 0);
    signal uart0_cyc_in  : std_logic;
    signal uart0_stb_in  : std_logic;
    signal uart0_we_in   : std_logic;
    signal uart0_ack_out : std_logic;

    -- Main memory signals:
    signal main_memory_adr_in  : std_logic_vector(positive(ceil(log2(real(MEMORY_SIZE))))-1 downto 0);
    signal main_memory_dat_in  : std_logic_vector(63 downto 0);
    signal main_memory_dat_out : std_logic_vector(63 downto 0);
    signal main_memory_cyc_in  : std_logic;
    signal main_memory_stb_in  : std_logic;
    signal main_memory_sel_in  : std_logic_vector(7 downto 0);
    signal main_memory_we_in   : std_logic;
    signal main_memory_ack_out : std_logic;

    -- Selected peripheral on the interconnect:
    type intercon_peripheral_type is (
	PERIPHERAL_UART0, PERIPHERAL_MAIN_MEMORY, PERIPHERAL_ERROR,
	PERIPHERAL_NONE);
    signal intercon_peripheral : intercon_peripheral_type := PERIPHERAL_NONE;

    -- Interconnect address decoder state:
    signal intercon_busy : boolean := false;

begin

    address_decoder: process(system_clk)
    begin
	if rising_edge(system_clk) then
	    if rst = '1' then
		intercon_peripheral <= PERIPHERAL_NONE;
		intercon_busy <= false;
	    else
		if not intercon_busy then
		    if processor_cyc_out = '1' then
			intercon_busy <= true;

			if processor_adr_out(31 downto 24) = x"00" then -- Main memory space
			    intercon_peripheral <= PERIPHERAL_MAIN_MEMORY;
			elsif processor_adr_out(31 downto 24) = x"c0" then -- Peripheral memory space
			    case processor_adr_out(15 downto 12) is
			    when x"2" =>
				intercon_peripheral <= PERIPHERAL_UART0;
			    when others => -- Invalid address - delegated to the error peripheral
				intercon_peripheral <= PERIPHERAL_ERROR;
			    end case;
			else
			    intercon_peripheral <= PERIPHERAL_ERROR;
			end if;
		    else
			intercon_peripheral <= PERIPHERAL_NONE;
		    end if;
		else
		    if processor_cyc_out = '0' then
			intercon_busy <= false;
			intercon_peripheral <= PERIPHERAL_NONE;
		    end if;
		end if;
	    end if;
	end if;
    end process address_decoder;

    processor_intercon: process(all)
    begin
	case intercon_peripheral is
	when PERIPHERAL_UART0 =>
	    processor_ack_in <= uart0_ack_out;
	    processor_dat_in <= x"00000000000000" & uart0_dat_out;
	when PERIPHERAL_MAIN_MEMORY =>
	    processor_ack_in <= main_memory_ack_out;
	    processor_dat_in <= main_memory_dat_out;
	when PERIPHERAL_NONE =>
	    processor_ack_in <= '0';
	    processor_dat_in <= (others => '0');
	when others =>
	    processor_ack_in <= '0';
	    processor_dat_in <= (others => '0');
	end case;
    end process processor_intercon;

    processor: entity work.core
	port map(
	    clk => system_clk,
	    rst => rst,
	    wishbone_insn_in => wishbone_icore_in,
	    wishbone_insn_out => wishbone_icore_out,
	    wishbone_data_in => wishbone_dcore_in,
	    wishbone_data_out => wishbone_dcore_out
	    );

    wishbone_arbiter_0: entity work.wishbone_arbiter
	port map(
	    clk => system_clk,
	    rst => rst,
	    wb1_in => wishbone_dcore_out,
	    wb1_out => wishbone_dcore_in,
	    wb2_in => wishbone_icore_out,
	    wb2_out => wishbone_icore_in,
	    wb_out => wishbone_proc_out,
	    wb_in => wishbone_proc_in
	    );
    processor_adr_out <= wishbone_proc_out.adr;
    processor_dat_out <= wishbone_proc_out.dat;
    processor_sel_out <= wishbone_proc_out.sel;
    processor_cyc_out <= wishbone_proc_out.cyc;
    processor_stb_out <= wishbone_proc_out.stb;
    processor_we_out <= wishbone_proc_out.we;
    wishbone_proc_in.dat <= processor_dat_in;
    wishbone_proc_in.ack <= processor_ack_in;

    uart0: entity work.pp_soc_uart
	generic map(
	    FIFO_DEPTH => 32
	    )
	port map(
	    clk => system_clk,
	    reset => rst,
	    txd => uart0_txd,
	    rxd => uart0_rxd,
	    wb_adr_in => uart0_adr_in,
	    wb_dat_in => uart0_dat_in,
	    wb_dat_out => uart0_dat_out,
	    wb_cyc_in => uart0_cyc_in,
	    wb_stb_in => uart0_stb_in,
	    wb_we_in => uart0_we_in,
	    wb_ack_out => uart0_ack_out
	    );
    uart0_adr_in <= processor_adr_out(uart0_adr_in'range);
    uart0_dat_in <= processor_dat_out(7 downto 0);
    uart0_we_in  <= processor_we_out;
    uart0_cyc_in <= processor_cyc_out when intercon_peripheral = PERIPHERAL_UART0 else '0';
    uart0_stb_in <= processor_stb_out when intercon_peripheral = PERIPHERAL_UART0 else '0';

    main_memory: entity work.pp_soc_memory
	generic map(
	    MEMORY_SIZE   => MEMORY_SIZE,
	    RAM_INIT_FILE => RAM_INIT_FILE
	    )
	port map(
	    clk => system_clk,
	    reset => rst,
	    wb_adr_in => main_memory_adr_in,
	    wb_dat_in => main_memory_dat_in,
	    wb_dat_out => main_memory_dat_out,
	    wb_cyc_in => main_memory_cyc_in,
	    wb_stb_in => main_memory_stb_in,
	    wb_sel_in => main_memory_sel_in,
	    wb_we_in => main_memory_we_in,
	    wb_ack_out => main_memory_ack_out
	    );
    main_memory_adr_in <= processor_adr_out(main_memory_adr_in'range);
    main_memory_dat_in <= processor_dat_out;
    main_memory_we_in  <= processor_we_out;
    main_memory_sel_in <= processor_sel_out;
    main_memory_cyc_in <= processor_cyc_out when
			  intercon_peripheral = PERIPHERAL_MAIN_MEMORY else '0';
    main_memory_stb_in <= processor_stb_out when
			  intercon_peripheral = PERIPHERAL_MAIN_MEMORY else '0';

end architecture behaviour;
