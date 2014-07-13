# Sup Filters
#
# Copyright (c) 2010 John Croisant
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


module SupFilters

  def self.filter_message( message, filters=:default )
    filters = load_filters(filters)

    if filters.nil?
      return 
    end

    filters.each do |condition, action|
      if condition.matches?(message)
        #puts "Message '#{message.subj}' matches #{condition.inspect}"
        action.apply(message)
      end
    end
  end

  def self.load_filters( filters )
    @cached_filters ||= {}

    unless filters.is_a? Hash
      filename = (if filters == :default
                    # Default is ~/.sup/filters.yaml
                    File.join( Redwood::BASE_DIR, "filters.yaml" )
                  else
                    filters
                  end)

      if @cached_filters[filename]
        filters = @cached_filters[filename]
      else
        unless File.exists?( filename )
          puts "Filters file does not exist: #{filename}"
          return
        end
        require 'yaml'
        y = YAML.load_file(filename)
        filters = parse_filters(y)
        if filters.empty?
          return
        end
        @cached_filters[filename] = filters
      end
    end

    return filters
  end

  def self.parse_filters( filters )
    result = {}
    filters.each do |condition, action|
      r = parse_condition(condition)
      #puts "Parsed condition: #{r.inspect}"
      a = parse_action(action)
      #puts "Parsed action: #{a.inspect}"
      if !r
        puts "Invalid condition: #{condition.inspect}"
      elsif !a
        puts "Invalid action: #{action.inspect}"
      else
        result[r] = a
      end
    end
    result
  end

  def self.split_descriptor( str )
    match = /(-?)([A-Za-z_-]+)(?::(.*))?/.match(str)
    return (match and match.captures)
  end

  def self.parse_condition( condition )
    if condition.is_a? Array
      MultiCondition.new( condition.collect{|r| parse_condition(r)} )
    else
      parts = split_descriptor(condition)
      return nil unless parts
      prefix, condition, param = *parts

      (case condition
       when "match";   MatchCondition
       when "from";    FromCondition
       when "to";      ToCondition
       when "subj";    SubjCondition
       when "body";    BodyCondition
       when "list";    ListCondition
       when "label";   LabelCondition
       when "spam";    SpamCondition
       when "inbox";   InboxCondition
       when "deleted"; DeletedCondition
       when "starred"; StarredCondition
       else;          return nil
       end).new(prefix, param)
    end
  end

  def self.parse_action( action )
    if action.is_a? Array
      MultiAction.new( action.collect{|a| parse_action(a)} )
    else
      parts = split_descriptor(action)
      return nil unless parts
      prefix, action, param = *parts

      (case action
       when "label", /^L$/i;  LabelAction
       when "inbox";          InboxAction
       when "unread";         UnreadAction
       when "read";           ReadAction
       when "star";           StarAction
       when "spam";           SpamAction
       when /deleted?$/;      DeleteAction
       else;                  return nil
       end).new(prefix, param)
    end
  end



  # CONDITIONS

  class Condition
    def initialize( prefix, param )
      @param = param
      @param_re = Regexp.new(@param, Regexp::IGNORECASE) if param
      @invert = (prefix == "-")
    end
    def matches?( message )
      @invert ? (!test(message)) : (test(message))
    end
    def test( message )
      # override this in child classes
    end
  end

  class MultiCondition < Condition
    def initialize( conditions )
      @conditions = conditions.compact
    end
    def matches?( message )
      @conditions.all?{ |r| r.matches?(message) }
    end
  end

  class MatchCondition < Condition
    def test( message )
      @param_re =~ message.raw_message
    end
  end

  class FromCondition < Condition
    def test( message )
      @param_re =~ message.from.to_s
    end
  end

  class ToCondition < Condition
    def test( message )
      @param_re =~ message.to.to_s
    end
  end

  class SubjCondition < Condition
    def test( message )
      @param_re =~ message.subj
    end
  end

  ## Not available because I can't figure out how to access the
  ## message body. :\
  class BodyCondition < Condition
    def test( message )
      @param_re =~ message.raw_message
    end
  end

  class ListCondition < Condition
    def test( message )
      @param_re =~ message.list_address.to_s
    end
  end

  class LabelCondition < Condition
    def test( message )
      message.has_label? @param
    end
  end

  class SpamCondition < Condition
    def test( message )
      message.has_label? "spam"
    end
  end

  class InboxCondition < Condition
    def test( message )
      message.has_label? "inbox"
    end
  end

  class DeletedCondition < Condition
    def test( message )
      message.has_label? "deleted"
    end
  end

  class StarredCondition < Condition
    def test( message )
      message.has_label? "starred"
    end
  end



  # ACTIONS

  class Action
    def initialize(prefix, param)
      @param = param
      @param_re = Regexp.new(@param, Regexp::IGNORECASE) if param
      @invert = (prefix == "-")
    end
    def apply( message )
      # override this in child classes
    end
  end

  class MultiAction < Action
    def initialize( actions )
      @actions = actions.compact
    end
    def apply( message )
      @actions.each{ |a| a.apply(message) }
    end
  end

  class LabelAction < Action
    def apply( message )
      if @body == "*"
        if @invert
          # Remove all current labels.
          message.labels = Set.new
        else
          # Error. "label:*" is invalid.
        end
        return
      end

      if @invert
        message.remove_label @param
      else
        message.add_label @param
      end
    end
  end

  class InboxAction < Action
    def apply( message )
      if @invert
        message.remove_label "inbox"
      else
        message.add_label "inbox"
      end
    end
  end

  class UnreadAction < Action
    def apply( message )
      if @invert
        message.remove_label "unread"
      else
        message.add_label "unread"
      end
    end
  end

  # Opposite of UnreadAction, for convenience.
  class ReadAction < Action
    def apply( message )
      if @invert
        message.add_label "unread"
      else
        message.remove_label "unread"
      end
    end
  end

  class StarAction < Action
    def apply( message )
      if @invert
        message.add_label "starred"
      else
        message.remove_label "starred"
      end
    end
  end

  class SpamAction < Action
    def apply( message )
      if @invert
        message.remove_label "spam"
      else
        message.add_label "spam"
        message.remove_label "inbox"
      end
    end
  end

  class DeleteAction < Action
    def apply( message )
      if @invert
        message.remove_label "deleted"
      else
        message.add_label "deleted"
        message.remove_label "inbox"
      end
    end
  end

end
