require 'active_shipping'
require 'yaml'
require 'csv'
require 'pp'
require 'json'
# require 'marshal'

def intl?(n)
  n.length == 13
end

def domestic?(n)
  n.length == 22
end

nums = []
times = []
CSV.foreach('query_result.csv', headers: true) do |row|
  yml = YAML.load(row[0])
  next unless yml
  num = yml[0]
  num.gsub!(/\s/,'')
  next unless intl?(num) || domestic?(num)
  nums << num
  times << Time.parse(row[1])
  # times << Time.now
end
nums.uniq!
# puts nums

def chunk_track(usps, nums)
  out = []
  last_batch = nil
  nums.each_slice(9) do |batch|
    STDERR.print '.'
    last_batch = batch
    batch_infos = batch.map {|n| {number: n}}
    out.concat(usps.batch_find_tracking_info(batch_infos))
  end
  STDERR.puts ''
  out
rescue SignalException => e
  out
rescue => e
  p last_batch
  STDERR.puts e.inspect
  STDERR.puts e.backtrace
  out
end

def format_ev(ev)
  {
    msg: ev.name,
    time: ev.time,
    country: ev.location.country.code(:alpha2).to_s,
  }
end

def format_res(res, num, time)
  base = {
    num: num,
    time: time,
  }
  if res.success?
    infos = res.params["TrackResponse"]["TrackInfo"]
    infos = [infos] unless infos.is_a? Array
    params = infos.select { |e| e['ID'] == num }.first
    base.merge!({
        class: params['Class'],
        ddate: res.actual_delivery_date,
        first: format_ev(res.shipment_events.first),
        last: format_ev(res.shipment_events.last),
      })
  else
    base.merge!({
      msg: res.message[0..55]
      })
  end
rescue => e
  p num
  # p res
  p infos.map { |e| e['ID'] }
  STDERR.puts e.inspect
  STDERR.puts e.backtrace
  base.merge!({fail: true})
end

def do_job(nums, times)
  if File.exist?('data.json')
    dump = JSON.load(IO.read('data.json'))
    start = dump.length
  else
    dump = []
    start = 0
  end
  STDERR.puts "Starting at #{start}/#{nums.length}"

  # Use public active-shipping test key
  usps = ActiveShipping::USPS.new(:login => '677JADED7283')
  res = chunk_track(usps, nums[start..-1])
  # pp res[0..30].map.with_index {|e,i| [e.success?, e.status, nums[i], e.message, e.shipment_events.first ? e.shipment_events.first.time : nil]}
ensure
  dump.concat res.map.with_index { |e,i| format_res(e, nums[start+i], times[start+i]) }
  pp dump[-5..-1]
  File.open('data.json', 'w') {|f| f.print dump.to_json}
end

do_job(nums,times)
