-- A modifed version of:
-- https://github.com/Scalingo/lua-resty-rollbar

local http = require 'resty.http'
local json = require 'cjson'

local _M = {
  version  = '0.1.0',

  -- 	Rollbar severity levels as reported to the Rollbar API.
  CRIT  = 'critical',
  ERR   = 'error',
  WARN  = 'warning',
  INFO  = 'info',
  DEBUG = 'debug',
}


-- Token is the Rollbar access token under which all items will be reported. If Token is blank, no errors will be
-- reported to Rollbar.
local token = nil
-- 	Environment is the environment under which all items will be reported.
local environment = 'development'
-- 	Endpoint is the URL destination for all Rollbar item POST requests.
local endpoint = 'https://api.rollbar.com/api/1/item/'
local person_params = {}
local custom_trace = nil

local rollbar_initted = nil

-- gethostname tries to find the host name of the machine executing this code. It first tries to
-- call the C function gethostname using FFI. If it fails it tries the command /bin/hostname. If it
-- fails again, it returns an empty string.
local function gethostname()
  local ffi = require "ffi"
  local C = ffi.C

  ffi.cdef[[
  int gethostname(char *name, size_t len);
  ]]

  local size = 50
  local buf = ffi.new("unsigned char[?]", size)

  local res = C.gethostname(buf, size)
  if res == 0 then
    return ffi.string(buf, size)
  end

  local f = io.popen("/bin/hostname", "r")
  if f then
    local host = f:read("*l")
    f:close()

    return host
  end
  return ''
end

-- send_request is a function which sends the given message at the specified level to Rollbar.
-- This function should be call asynchronously with ngx.timer.at.
--
-- First argument of a function called with ngx.timer.at is premature
-- (https://github.com/openresty/lua-nginx-module#ngxtimerat)
local function send_request(_, level, title, stacktrace, request)
  local body = {
    access_token = token,
    data = {
      environment = environment,
      body = {
        message = {
          body = custom_trace or stacktrace,
        },
      },
      person = person_params,
      level = level,
      timestamp = ngx.now(),
      platform = 'linux',
      language = 'lua',
      framework = 'OpenResty',
      request = request,
      server = { host = gethostname() },
      title = title,
      notifier = {
        name    = 'lua-resty-rollbar',
        version = _M.version,
      },
    },
  }

  local httpc = http.new()
  local res, err = httpc:request_uri(endpoint, {
    method = 'POST',
    headers = {
      ['Content-Type'] = 'application/json',
      ['Accept'] = 'application/json, text/html;q=0.9',
    },
    ssl_verify = false,
    body = json.encode(body),
  })
  if not res then
    ngx.log(ngx.ERR, 'failed to send Rollbar error: ', err)
    return err
  end
  if res.status ~= 200 then
    ngx.log(ngx.ERR, 'invalid Rollbar response: ', res.status, ' - ', res.body)
    return 'invalid Rollbar response'
  end

  return false
end

-- isempty returns true if the given variable is nil or an empty string.
local function isempty(s)
  return s == nil or s == ''
end

-- set_token sets the token used by this client.
-- The value is a Rollbar access token with scope "post_server_item".
-- It is required to set this value before any of the other functions herein will be able to work
-- properly.
function _M.set_token(t)
  token = t
end

-- set_environment sets the environment under which all errors and messages will be submitted.
function _M.set_environment(env)
  environment = env
end

-- Set a user to appear in rollbar.
function _M.set_person(user)
  if not user then
    person_params = nil
  else
    person_params = {
      id = user.id,
      username = user.username,
      email = user.email
    }
  end
end

function _M.set_custom_trace(trace)
  custom_trace = trace
end

-- set_endpoint sets the endpoint to post items to.
function _M.set_endpoint(e)
  endpoint = e
end

-- report sends an error to Rollbar with the given level and title.
-- It fills the other fields using Nginx API for lua
-- (https://github.com/openresty/lua-nginx-module#nginx-api-for-lua).
function _M.report(level, title)
  if rollbar_initted == nil then
    if isempty(token) then
      rollbar_initted = false
      ngx.log(ngx.ERR, 'Rollbar token not set, no error sent to Rollbar')
      return
    else
      rollbar_initted = true
    end
  end

  if not rollbar_initted then
    return
  end

  if type(title) ~= 'string' then
    title = tostring(title)
  end

  local url = ngx.var.scheme..'://'..ngx.var.host..ngx.var.request_uri
  local method = ngx.req.get_method()
  local request = {
    url = url,
    method = method,
    headers = ngx.req.get_headers(),
    query_string = ngx.var.args,
    user_ip = ngx.var.remote_addr,
  }
  if method == 'GET' then
    request.GET = ngx.req.get_uri_args()
  elseif method == 'POST' then
    ngx.req.read_body()
    local args, err = ngx.req.get_post_args()
    if err then
      request.POST = 'ERROR READING POST ARGS'
    else
      request.POST = args
    end
  end

  -- create a light thread to send the HTTP request in background
  ngx.timer.at(0, send_request, level, title, debug.traceback(), request)
end

return _M
