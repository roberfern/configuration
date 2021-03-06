#!/bin/sh
# shellcheck disable=SC2039,SC2155,SC2173,SC1117

STOPPED=false
ETH_NIC='em0'

TEMP_WARN="60"
TEMP_CRIT="70"

_stop()
{
	STOPPED=true
}

_continue()
{
	STOPPED=false
}

is_nic_active()
{
	ifconfig "${1}" | \
		grep -qE '[[:space:]]status:[[:space:]](active|associated)'
}

vpn()
{
	if ! ifconfig tun0 > /dev/null 2>/dev/null ; then
		print_info 'VPN' vpn '#FF0000'
	else
		print_info 'VPN' vpn '#00FF00'
	fi
}

get_ipv4()
{
	local NIC="${1}"

	# If the nic is down, print nothing
	if ! is_nic_active "${NIC}" ; then
		return
	fi

	local ipv4=$(ifconfig "${NIC}" | \
		grep -E '[[:space:]]inet[[:space:]]' | awk '{ print $2}')
	local mask=$(ifconfig "${NIC}" | \
		grep -E '[[:space:]]inet[[:space:]]' | awk '{ print $4}')
	local bits=0

	mask=$(printf "%d" "${mask}")
	while [ "${mask}" -gt 0 ] ; do
		if [ "$((mask % 2))" -eq 1 ]; then
			: $((bits += 1))
		fi
		: $((mask /= 2))
	done
	echo "${ipv4} / ${bits}"
}

print_info()
{
	local full_text=${1:?full_text is mandatory}
	local name=${2:-}
	local color=${3:-}

	printf '{'
	if [ "${name}" ] ; then
		printf '"name": "%s",' "${name}"
	fi
	if [ "${color}" ] ; then
		printf '"color": "%s",' "${color}"
	fi

	printf '"full_text": "%s"}' "${full_text}"
}

ipv6()
{
	local ipv6=$(ifconfig "${ETH_NIC}" | \
		grep 'inet6' | awk '{ print $2 "/" $4 }')
	if [ "${ipv6}" ] ; then
		print_info "IPv6: ${ipv6}" ipv6 "#00FF00"
	else
		print_info "No IPv6" ipv6 "#FF0000"
	fi
}

zfs_disk()
{
	local zpool_space=$(zpool list -H zroot | awk '{ print $4 "/" $2 }')
	local color

	if zpool status -x | grep -q "all pools are healthy" ; then
		color="#00FF00"
	else
		color="#FF0000"
	fi
	print_info "${zpool_space}" zfs_disk "${color}"
}

wlan()
{
	# Do it on the laptop
	local wlan_ssid="$(ifconfig wlan0 | grep -E '[[:space:]]ssid[[:space:]]' |\
		awk '{ print $2; }')"
	local ipv4=$(get_ipv4 wlan0)

	if [ "${wlan_ssid}" ] && [ "${wlan_ssid}" != '""' ] ;then
		wlan_ssid=$(echo "${wlan_ssid}" | sed "s,\",',g")
		print_info "W: ${ipv4} (${wlan_ssid})" wlan '#00FF00'
	else
		print_info 'W: down' wlan '#FF0000'
	fi
}

ipv4()
{
	local ipv4=$(get_ipv4 "${ETH_NIC}")

	if is_nic_active "${ETH_NIC}" && [ "${ipv4}" ] ; then
		print_info "E: ${ipv4}" ipv4 '#00FF00'
	else
		print_info "E: down" ipv4 '#FF0000'
	fi
}

battery()
{
	if sysctl hw.acpi.battery > /dev/null 2> /dev/null ; then
		local life=$(sysctl -n hw.acpi.battery.life)
		local bat_time=$(sysctl -n hw.acpi.battery.time)
		local bat_time_txt='' units=0 color=""

		if [ "${life}" -lt 10 ] ; then
			color='#FF0000'
		elif [ "${life}" -lt 25 ] ; then
			color='#FFFF00'
		fi
		while [ "${bat_time}" -gt 0 ] ; do
			case "${units}" in
			0)
				bat_time_txt="$((bat_time % 60))m"
				: $((bat_time /= 60))
				;;
			1)
				bat_time_txt="$((bat_time % 24))h ${bat_time_txt}"
				: $((bat_time /= 24))
				;;
			2)
				bat_time_txt="${bat_time}d ${bat_time_txt}"
				bat_time=0
				;;
			esac
			: $((units += 1))
		done
		print_info "B: ${life}% ${bat_time_txt}" battery "${color}"
	else
		print_info 'B: none' battery
	fi
}

temp()
{
	local cpu_temp=$(sysctl -n dev.cpu.0.temperature)
	local color

	if [ "${cpu_temp%%.*}" -gt "${TEMP_CRIT}" ] ;then
		color="#FF0000"
	elif [ "${cpu_temp%%.*}" -gt "${TEMP_WARN}" ] ; then
		color="#FFFF00"
	else
		color="#00FF00"
	fi
	print_info "${cpu_temp}" temp "${color}"
}

time_berlin()
{
	local _time=$(env TZ="Europe/Berlin" date '+%Z: %H:%M')
	print_info "${_time}" 'time'
}

date_time_locale()
{
	local date=$(date '+%Z: %d.%m.%Y %H:%M')
	print_info "${date}" locale_date
}

_uptime()
{
	local up_time=$(uptime | awk '{ print $3 " " $4}' | sed 's/,.*//')
	print_info "Uptime: ${up_time}" uptime
}

packages()
{
	if ! [ -s "/var/log/pkg-upgrade" ] ; then
		print_info "PKG updated" pkgs "#00FF00"
	else
		print_info "New PKGS" pkgs "#FFFF00"
	fi
}

freebsd_version()
{
	local system_version

	system_version=$(uname -or)
	print_info "${system_version}" updates "#FFFFFF"
}

trap _stop STOP
trap  CONT

check_pkgs &
echo '{"version":1}'
echo '['
while true ; do
	if ! ${STOPPED} ; then
		printf "[%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s],\n" \
			"$(_uptime)" \
			"$(freebsd_version)" \
			"$(vpn)" \
			"$(ipv6)" \
			"$(ipv4)" \
			"$(wlan)" \
			"$(zfs_disk)" \
			"$(battery)" \
			"$(temp)" \
			"$(date_time_locale)" \
			"$(time_berlin)"
	fi
	sleep 5
done
echo ']'
