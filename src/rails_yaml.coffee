exports.version = '0.0.1'

# --- Helpers

context = (str)->
  return '' if (typeof str != 'string')
  str = str.substr(0, 25).replace(/(\n|\r\n)/g, '\\n').replace(/"/g, '\\\"')
  return 'near "' + str + '"'

TOKENS = [
  ['comment', /^#[^\n]*/],
  ['indent', /^(?:\n|\r\n)( *)/],
  ['space', /^ +/],
  ['true', /^\b(enabled|true|yes|on)\b/],
  ['false', /^\b(disabled|false|no|off)\b/],
  ['null', /^\b(null|Null|NULL|nil)\b/],
  ['string', /^"(.*?)"/],
  ['string', /^'(.*?)'/],
  ['timestamp', /^((\d{4})-(\d\d?)-(\d\d?)(?:(?:[ \t]+)(\d\d?):(\d\d)(?::(\d\d))?)?)/],
  ['float', /^(\d+\.\d+)/],
  ['int', /^(\d+)/],
  ['doc', /^---/],
  ['define', /^\&(\w+)/],
  ['ref', /^<<:\s*\*(\w+)/],
  [',', /^,/],
  ['{', /^\{(?![^\n\}]*\}[^\n]*[^\s\n\}])/],
  ['}', /^\}/],
  ['[', /^\[(?![^\n\]]*\][^\n]*[^\s\n\]])/],
  [']', /^\]/],
  ['-', /^\-/],
  [':', /^[:]/],
  ['string', /^(?![^:\n\s]*:[^\/]{2})(([^:,\]\}\n\s]|(?!\n)\s(?!\s*?\n)|:\/\/|,(?=[^\n]*\s*[^\]\}\s\n]\s*\n)|[\]\}](?=[^\n]*\s*[^\]\}\s\n]\s*\n))*)(?=[,:\]\}\s\n]|$)/], 
  ['id', /^([\w][\w -]*)/]
]

exports.tokenize = (str)->
  indents = 0
  lastIndents = 0
  stack = []
  indentAmount = -1
  
  while str.length
    #console.log "input: #{context(str.substr(0,25))}"
    
    for tok, i in TOKENS
      captures = str.match( tok[1] )
      #console.log "tokenType: #{tok[0]}: #{tok[1]}: #{captures}"
      continue unless captures?
      #console.log "type: #{tok[0]}"
      
      token = [tok[0], captures]
      str = str.replace(captures[0], '')
      
      switch token[0]
        when 'comment'
          ignore = true
        when 'indent'
          lastIndents = indents

          if indentAmount <= 0
            indentAmount = token[1][1].length
            #console.log("indentAmount: " + indentAmount)

          if indentAmount > 0
            indents = token[1][1].length / indentAmount
            
            if indents == lastIndents
              ignore = true
              
            else if indents > lastIndents + 1
              throw new SyntaxError('invalid indentation, got ' + indents + ' instead of ' + (lastIndents + 1))
              
            else if indents < lastIndents
              input = token[1].input
              token = ['dedent']
              token.input = input
              while --lastIndents > indents
                stack.push(token)
          else
            ignore = true
      break
    
    if i >= TOKENS.length
      console.error "Unmatch!!: #{context(str)}"
      throw new SyntaxError(context(str))
      
    if !ignore
      if token
        stack.push(token)
        token = null
      else 
        throw new SyntaxError(context(str))
        
    ignore = false
    
  return stack

class Parser
  constructor: (tokens)->
    @tokens = tokens

  peek: -> @tokens[0]
  advance: -> @tokens.shift()
  advanceValue: -> @advance()[1][1]
  accept: (type)->
    @advance() if @peekType(type)
  expect: (type, msg)->
    return if @accept(type)
    throw new Error(msg + ', ' + context(@peek()[1].input))
  peekType: (val)->
    @tokens[0] && @tokens[0][0] == val
  ignoreSpace: ->
    @advance() while @peekType('space')
  ignoreWhitespace: ->
    @advance() while @peekType('space') || @peekType('indent') || @peekType('dedent')
  parse: ->
    #console.log "parse: #{@peek()[0]}"
    
    switch @peek()[0]
      when 'doc'
        @parseDoc()
      when '-'
        @parseList()
      when '{'
        @parseInlineHash()
      when '['
        @parseInlineList()
      when 'id'
        @parseHash()
      when 'string'
        @advanceValue()
      when 'timestamp'
        @parseTimestamp()
      when 'float'
        parseFloat(@advanceValue())
      when 'int'
        parseInt(@advanceValue())
      when 'ref'
        @parseHash()
      when 'true'
        @advanceValue()
        true
      when 'false'
        @advanceValue()
        false
      when 'null'
        @advanceValue()
        null

  parseDoc: ->
    if @accept('doc')
      @expect('indent', 'expected indent after document')
      val = @parse()
      @expect('dedent', 'document not properly dedented')
    else
      @ignoreWhitespace()
      val = @parseHash()
    val

  parseHash: ->
    hash = {}
    
    while true
      if @peekType('id') && (id = @advanceValue())
        #console.log "hash-id: #{id}"
        @expect(':', 'expected semi-colon after id')
        @ignoreSpace()
        
        ref = null
        if @peekType('define')
          @_define ?= {}
          ref = @advanceValue()
        
        if @accept('indent')
          #console.log "hash-nest: start"
          hash[id] = @parse()
          @expect('dedent', 'hash not properly dedented')
          #console.log "hash-nest: end"
        else
          hash[id] = @parse()
  
        @_define[ ref ] = hash[id] if ref?
  
        @ignoreSpace()
      else if @peekType('ref')
        val = @parseRef()
        hash[n] = v for n,v of val
      else if @peekType('indent')
        @ignoreWhitespace()
      else
        break

    hash

  parseRef: ->
    ref = @advanceValue()
    #console.log "ref: #{ref}"
    
    @_define ?= {}
    @ignoreSpace()
    ret = @_define[ ref ]
    #console.log "#{ref} -> #{JSON.stringify(ret)}"
    ret

  parseInlineHash: ->
    hash = {}
    i = 0
    @accept('{')
    while !@accept('}')
      @ignoreSpace()
      
      if i
        @expect(',', 'expected comma')
        
      @ignoreWhitespace()
      
      if @peekType('id') && (id = @advanceValue())
        @expect(':', 'expected semi-colon after id')
        @ignoreSpace()
        hash[id] = @parse()
        @ignoreWhitespace()
      
      ++i
    hash

  parseList: ->
    list = []
    while @accept('-')
      @ignoreSpace()
      if @accept('indent')
        list.push(@parse())
        @expect('dedent', 'list item not properly dedented')
      else
        list.push(@parse())
      @ignoreSpace()
    list

  parseInlineList: ->
    list = []
    i = 0
    @accept('[')
    while !@accept(']')
      @ignoreSpace()
      if i
        @expect(',', 'expected comma')
      @ignoreSpace()
      list.push(@parse())
      @ignoreSpace()
      ++i
    list

  parseTimestamp: ->
    token = @advance()[1]
    date = new Date()
    year = token[2]
    month = token[3]
    day = token[4]
    hour = token[5] ? 0 
    min = token[6] ? 0
    sec = token[7] ? 0
  
    date.setUTCFullYear(year, month-1, day)
    date.setUTCHours(hour)
    date.setUTCMinutes(min)
    date.setUTCSeconds(sec)
    date.setUTCMilliseconds(0)
    date

exports.eval = (str)->
  tokens = exports.tokenize(str)
  new Parser(tokens).parseDoc()
  