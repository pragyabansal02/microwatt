library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity zero_counter is
    port (
	rs          : in std_ulogic_vector(63 downto 0);
	count_right : in std_ulogic;
	is_32bit    : in std_ulogic;
	result      : out std_ulogic_vector(63 downto 0)
	);
end entity zero_counter;

architecture behaviour of zero_counter is
    signal y, z     : std_ulogic_vector(3 downto 0);
    signal v16      : std_ulogic_vector(15 downto 0);
    signal v4       : std_ulogic_vector(3 downto 0);
    signal sel      : std_ulogic_vector(5 downto 0);

    -- Return the index of the leftmost or rightmost 1 in a set of 4 bits.
    -- Assumes v is not "0000"; if it is, return (right ? "11" : "00").
    function encoder(v: std_ulogic_vector(3 downto 0); right: std_ulogic) return std_ulogic_vector is
    begin
	if right = '0' then
	    if v(3) = '1' then
		return "11";
	    elsif v(2) = '1' then
		return "10";
	    elsif v(1) = '1' then
		return "01";
	    else
		return "00";
	    end if;
	else
	    if v(0) = '1' then
		return "00";
	    elsif v(1) = '1' then
		return "01";
	    elsif v(2) = '1' then
		return "10";
	    else
		return "11";
	    end if;
	end if;
    end;

begin
    zerocounter0: process(all)
    begin
	-- Test 4 groups of 16 bits each.
	-- The top 2 groups are considered to be zero in 32-bit mode.
	z(0) <= or (rs(15 downto 0));
	z(1) <= or (rs(31 downto 16));
	z(2) <= or (rs(47 downto 32));
	z(3) <= or (rs(63 downto 48));
        if is_32bit = '0' then
            sel(5 downto 4) <= encoder(z, count_right);
        else
            sel(5) <= '0';
            if count_right = '0' then
                sel(4) <= z(1);
            else
                sel(4) <= not z(0);
            end if;
        end if;

	-- Select the leftmost/rightmost non-zero group of 16 bits
	case sel(5 downto 4) is
	    when "00" =>
		v16 <= rs(15 downto 0);
	    when "01" =>
		v16 <= rs(31 downto 16);
	    when "10" =>
		v16 <= rs(47 downto 32);
	    when others =>
		v16 <= rs(63 downto 48);
	end case;

	-- Test 4 groups of 4 bits
	y(0) <= or (v16(3 downto 0));
	y(1) <= or (v16(7 downto 4));
	y(2) <= or (v16(11 downto 8));
	y(3) <= or (v16(15 downto 12));
	sel(3 downto 2) <= encoder(y, count_right);

	-- Select the leftmost/rightmost non-zero group of 4 bits
	case sel(3 downto 2) is
	    when "00" =>
		v4 <= v16(3 downto 0);
	    when "01" =>
		v4 <= v16(7 downto 4);
	    when "10" =>
		v4 <= v16(11 downto 8);
	    when others =>
		v4 <= v16(15 downto 12);
	end case;

	sel(1 downto 0) <= encoder(v4, count_right);

	-- sel is now the index of the leftmost/rightmost 1 bit in rs
	if v4 = "0000" then
	    -- operand is zero, return 32 for 32-bit, else 64
	    result <= x"00000000000000" & '0' & not is_32bit & is_32bit & "00000";
	elsif count_right = '0' then
	    -- return (63 - sel), trimmed to 5 bits in 32-bit mode
	    result <= x"00000000000000" & "00" & (not sel(5) and not is_32bit) & not sel(4 downto 0);
	else
	    result <= x"00000000000000" & "00" & sel;
	end if;

    end process;
end behaviour;
