require './lib/colorlib.rb'

module Colors
  extend Discordrb::Commands::CommandContainer

  ColorRole = Struct.new(:idx, :role, :id)

  def self.get_colors(event)
    bot_roles = event.server.roles.filter { _1.name.ends_with? '[c]' }.sort_by(&:position).reverse
    default = bot_roles.map { ColorRole.new(nil, _1, _1.id) }

    extra_conf = ExtraColorRole.where(server_id: event.server.id).map(&:role_id) || []
    extra = extra_conf.map { ColorRole.new(nil, event.server.role(_1), _1) }

    colors = default + extra

    colors.each.with_index { |cr, idx| cr.idx = idx }

    [colors, default, extra]
  end

  def self.assign_role(event, role_list, role, name)
    if event.author.roles.include? role
      event.channel.send_embed { _1.description = "You already have that #{name}." }
    else
      event.author.roles -= role_list
      event.author.add_role role
      event.channel.send_embed { _1.description = "Your #{name} is now **#{role.name}**." }
    end
  end

  def self.color_ring(l, size, num)
    angle = 2 * Math::PI / num

    (0...num).map do
      this_angle = angle * _1
      a = size * Math.cos(this_angle)
      b = size * Math.sin(this_angle)

      ColorLib.lab_to_hex [l, a, b]
    end
  end

  command :color, {
    aliases: [:c],
    help_available: true,
    description: 'Sets your user color',
    usage: '.c <color>',
    min_args: 1
  } do |event, *args|
    log(event)

    colors, = Colors.get_colors(event)

    req = args.join(' ')

    requested_color = nil

    begin
      # Find color by index
      idx = Integer(req)
      requested_color = colors.find { _1.idx == idx }
    rescue ArgumentError
      # Find color by name
      requested_color = colors.find { _1.role.name.downcase.start_with? req.downcase }
    end

    # Role for the requested color
    rc = requested_color.role || (return 'Color not found.')

    Colors.assign_role(event, colors.map { _1.role }, rc, 'color')
  end

  command :closestcolor, {
    aliases: [:cc],
    help_available: true,
    description: 'Gives you the closest color',
    usage: '.cc <color>',
    min_args: 1,
    max_args: 1
  } do |event, color|
    log(event)

    colors, = Colors.get_colors(event)

    labs = colors.sort_by { _1.idx }.map { ColorLib.hex_to_lab _1.role.color.hex.rjust(6, '0') }
    compare = ColorLib.hex_to_lab(color)

    de = labs.map { ColorLib.cie76(compare, _1) }
    min = de.each.with_index.min_by { |val, _idx| val }

    color = colors.find { _1.idx == min[1] }

    event.channel.send_embed { _1.description = "Closest color found: `##{color.role.color.hex.rjust(6, '0')}`." }
    Colors.assign_role(event, colors.map { _1.role }, color.role, 'color')
  end

  command :listcolors, {
    aliases: [:lc],
    help_available: true,
    description: 'Lists colors',
    usage: '.lc',
    min_args: 0,
    max_args: 0
  } do |event, *_args|
    log(event)

    colors, = Colors.get_colors(event)

    # Formatted list of the colors
    list = colors.sort_by { _1.idx }.map do |c|
      idx = c.idx.to_s.rjust(2)
      r = c.role
      "#{idx}: ##{r.color.hex.rjust(6, '0')} #{r.name}"
    end

    event.channel.send_embed do |m|
      m.title = 'All colors'
      m.description = "```#{list.join "\n"}```"
    end
  end

  command :createcolorroles, {
    aliases: [:ccr],
    help_available: false,
    description: 'Creates color roles',
    usage: '.createcolorroles <lightness> <spread> <count>',
    min_args: 3,
    max_args: 3
  } do |event, *args|
    g = event.server

    return 'You do not have the required permissions for this.' unless event.author.permission?(:administrator)

    g.roles.filter { _1.name.ends_with? '[c]' }.each do
      event.respond "Deleting existing color role `#{_1.name}`."
      _1.delete
    end

    l = args[0].to_f
    size = args[1].to_f
    num = args[2].to_i

    colors = Colors.color_ring(l, size, num)

    colors.each.with_index do |hex, idx|
      event.server.create_role(
        name: "color#{idx} [c]",
        colour: Discordrb::ColourRGB.new(hex),
        permissions: 0,
        reason: 'Generating color roles'
      )
      event.respond "Created role `color#{idx}` with color `##{hex}`."
    end

    "Created #{colors.size} roles."
  end

  command :randcolors, {
    aliases: [:rc],
    help_available: false,
    description: 'Randomizes user colors',
    usage: '.rc',
    min_args: 0,
    max_args: 0
  } do |event|
    return 'You do not have the required permissions for this.' unless event.author.permission?(:administrator)

    users = event.server.members
    colors, default, = Colors.get_colors(event)

    counter = 0
    users.filter { (_1.roles & colors.map(&:role)).empty? }.each do |u|
      u.roles += [default.sample.role]
      counter += 1
    end

    event.channel.send_embed { _1.description = "Randomized colors for #{counter} users." }
  end
end

QBot.bot.member_join do |event|
  _, default, = Colors.get_colors(event)

  event.user.add_role(default.sample['role'])
end