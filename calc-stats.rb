require 'json'
require 'pp'
require 'gruff'
require 'time'

data = JSON.load(IO.read('data.json'))

def calc_fracs(stats, total_key, keys)
  total = stats[total_key].to_f
  keys.each do |k|
    stats[(k.to_s + "_of_" + total_key.to_s).intern] = stats[k]/total
  end
end

def successes(data)
  data.reject { |e| e['msg'] }
end

def ship_time(datum)
  start = Time.parse(datum['first']['time'])
  return Time.parse(datum['time']) if start.year == 2000
  start
end

def calc_stats(data)
  stats = {}
  stats[:total] = data.length
  success = successes(data)
  stats[:success] = success.length
  delivered = success.select { |e| e['last']['msg'] == 'DELIVERED' }
  stats[:delivered] = delivered.length
  stats[:lost] = stats[:success] - stats[:delivered]
  stats[:fail] = stats[:total] - stats[:success]

  times = delivered.map { |e| (Time.parse(e['last']['time'])-ship_time(e))/(60*60*24) }
  # pp times.zip(delivered).select { |e| e[0] > 300 }
  stats[:avg_transit_days] = (times.inject(:+)/stats[:delivered].to_f)

  calc_fracs(stats, :total, [:success,:delivered,:fail,:lost])
  calc_fracs(stats, :success, [:delivered,:lost])
  stats
end

def rotate(a_of_h)
  res = {}
  a_of_h.each do |h|
    h.each do |k,v|
      res[k] ||= []
      res[k] << v
    end
  end
  res
end

def graph(h_of_a, label_key, data_keys)
  g = Gruff::SideStackedBar.new('1000x600')
  g.marker_font_size = 9
  g.title_font_size = 22
  name = "#{data_keys.join('+')} by #{label_key}"
  g.title = name
  labels = h_of_a[:key].map.with_index { |e,i| [i,e] }.to_h
  g.labels = labels
  data_keys.each do |k|
    g.data(k, h_of_a[k])
  end
  g.write "graphs/#{name}.png"
end

def do_batch(batch,keys)
  stats = batch.map { |e| calc_stats(e) }
  stats.each_with_index {|e,i| e[:key] = keys[i]}
  # pp stats
  rotate(stats)
end

def by_mail_class(data)
  label = 'mail class'
  data = successes(data)
  groups = data.group_by { |e| e['class'] }
  keys = groups.keys.map { |e| (e||'Unknown').gsub(/<SUP>.*<\/SUP>/,'') }
  rot = do_batch(groups.values,keys)
  graph(rot, label, [:lost, :delivered])
  graph(rot, label, [:lost_of_total, :delivered_of_total])
  graph(rot, label, [:avg_transit_days])
end

def by_month(data)
  label = 'month'
  groups = data.group_by { |e| Time.parse(e['time']).strftime("%b") }.sort_by {|e| Time.parse(e[1].first['time'])}
  keys = groups.map(&:first).map(&:to_s)
  rot = do_batch(groups.map(&:last),keys)
  graph(rot, label, [:fail, :lost, :delivered])
  graph(rot, label, [:fail_of_total,:lost_of_total,:delivered_of_total])
  graph(rot, label, [:avg_transit_days])
end

pp calc_stats(data)
by_mail_class(data)
by_month(data)
