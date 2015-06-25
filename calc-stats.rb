require 'json'
require 'pp'
require 'gruff'
require 'time'

data = JSON.load(IO.read('data.json'))
# pp data.select {|e| !e['msg'] && !e['class']}
data.reject! {|e| !e['msg'] && !e['class']}

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

CLASSES = [:not_sent, :delivered, :probably_delivered, :legit_fail, :lost]

def calc_stats(data)
  stats = {}
  stats[:total] = data.length
  success = successes(data)
  stats[:success] = success.length
  delivered = success.select { |e| e['last']['msg'] == 'DELIVERED' }
  stats[:delivered] = 5
  stats[:fail] = stats[:total] - stats[:success]

  times = delivered.map { |e| (Time.parse(e['last']['time'])-ship_time(e))/(60*60*24) }
  # pp times.zip(delivered).select { |e| e[0] > 300 }
  stats[:avg_transit_days] = (times.inject(:+)/stats[:delivered].to_f)

  classes = success.map { |e| classify(e['last']['msg']) }
  CLASSES.each do |klass|
    stats[klass] = classes.count(klass)
  end
  stats[:not_lost] = stats[:success] - stats[:lost]
  stats[:not_lost_or_deliv] = stats[:success] - stats[:lost] - stats[:delivered]


  ags = CLASSES + [:not_lost, :not_lost_or_deliv]
  calc_fracs(stats, :total, [:success,:fail]+ags)
  calc_fracs(stats, :success, ags)
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

def graph(h_of_a, label_key, data_keys, klass = Gruff::SideStackedBar)
  g = klass.new('1000x600')
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
  stats
  # pp stats
  # rotate(stats)
end

def by_mail_class(data)
  label = 'mail class'
  data = successes(data)
  groups = data.group_by { |e| e['class'] }
  keys = groups.keys.map { |e| (e||'Unknown').gsub(/<SUP>.*<\/SUP>/,'') }
  by_x('mail class', groups.map(&:last), keys, true)
end

def by_x(label, values, keys, no_fail)
  puts "============ stats by #{label} ================"
  stats = do_batch(values,keys)
  pp stats
  rot = rotate(stats)

  graph(rot, label, [:fail, :lost, :delivered]) unless no_fail
  graph(rot, label, [:fail_of_total,:lost_of_total,:not_lost_of_total]) unless no_fail
  graph(rot, label, [:lost, :delivered])
  graph(rot, label, [:lost_of_total, :not_lost_or_deliv_of_total, :delivered_of_total])
  graph(rot, label, [:avg_transit_days])
  interesting_classes = (CLASSES-[:delivered]).map { |e| (e.to_s+"_of_success").intern  }
  graph(rot, label, interesting_classes, Gruff::SideBar)

  # groups.values.zip(keys).each do |vs,k|
  #     puts "======== '#{k}' fail states:"
  #     fail_states(vs)
  # end
end

def by_month(data)
  groups = data.group_by { |e| Time.parse(e['time']).strftime("%b") }.sort_by {|e| Time.parse(e[1].first['time'])}
  keys = groups.map(&:first).map(&:to_s)
  by_x('month', groups.map(&:last), keys, false)
end

def classify(state)
  case state
  when "PRE-SHIPMENT INFO SENT TO USPS","ORIGIN POST IS PREPARING SHIPMENT","SHIPPING LABEL CREATED"
    :not_sent
  when "ATTEMPTED DELIVERY - ITEM BEING HELD, ADDRESSEE BEING NOTIFIED","ADDRESSEE REQUESTS OWN PICK-UP - ITEM BEING HELD, ADDRESSEE BEING NOTIFIED", "DELIVERED","ATTEMPTED DELIVERY ABROAD"
    :delivered
  when "ATTEMPTED DELIVERY - SCHEDULED FOR ANOTHER DELIVERY ATTEMPT TODAY", "MISSED DELIVERY - WILL ATTEMPT DELIVERY ON NEXT WORKING DAY","ADDRESSEE NOT AVAILABLE - ADDRESSEE ADVISED TO PICK UP THE ITEM"
    :probably_delivered
  when "INCORRECT ADDRESS - ITEM RETURNED TO SENDER", "INCORRECT ADDRESS - ADDRESSEE'S ADDRESS BEING VERIFIED","PAYMENT OF CHARGES - ITEM BEING HELD, ADDRESSEE BEING NOTIFIED", "BUSINESS CLOSED", "NOTICE LEFT (NO AUTHORIZED RECIPIENT AVAILABLE)", "UNCLAIMED - ITEM RETURNED TO SENDER"
    :legit_fail
  else
    :lost
  end
end

def fail_states(data)
  success = successes(data)
  lost = success.reject { |e| e['last']['msg'] == 'DELIVERED' }
  groups = lost.group_by {|e| e['last']['msg'] }
  counts = groups.map { |e| [e[0],e[1].length, classify(e[0])] }.sort_by { |e| -e[1] }
  pp counts
end


pp calc_stats(data)
by_mail_class(data)
by_month(data)
puts "====== overall end states"
fail_states(data)
