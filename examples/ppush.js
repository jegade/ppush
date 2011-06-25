/*!
 * Based on pusher.js
 *
 * Copyright 2011, Pusher.com
 * Released under the MIT licence.
 */

if (typeof Function.prototype.scopedTo == 'undefined') {
    Function.prototype.scopedTo = function(context, args) {
        var f = this;
        return function() {
            return f.apply(context, Array.prototype.slice.call(args || []).concat(Array.prototype.slice.call(arguments)));
        };
    };
};

var PPush = function(server,port,secure, options) {

    this.server = server;
    this.secure = secure;
    this.ws_port   = port;
    this.wss_port   = port;

    this.options = options || {};
    this.path = '/ppush'; //?client=js&version=' + PPush.VERSION;
    this._id;
    this.channels = new PPush.Channels();
    this.global_channel = new PPush.Channel('pusher_global_channel')
    this.global_channel.global = true;
    this.secure = false;
    this.connected = false;
    this.retry_counter = 0;
    this.encrypted = this.secure ? true : false;
    if (PPush.isReady) this.connect();
    PPush.instances.push(this);

    //This is the new namespaced version
    this.bind('pusher:connection_established', function(data) {
        this.connected = true;
        this.retry_counter = 0;
        this.socket_id = data.socket_id;
        this.subscribeAll();
    }.scopedTo(this));

    this.bind('pusher:connection_disconnected', function() {
        for (var channel_name in this.channels.channels) {
            this.channels.channels[channel_name].disconnect()
        }
    }.scopedTo(this));

    this.bind('pusher:error', function(data) {
        PPush.debug("ERROR", data.message);
    });

};

PPush.instances = [];
PPush.prototype = {
    channel: function(name) {
        return this.channels.find(name);
    },

    connect: function() {
        if (this.encrypted || this.secure) {
            var url = "wss://" + PPush.host + ":" + PPush.wss_port + this.path;
        } else {
            var url = "ws://" + PPush.host + ":" + PPush.ws_port + this.path;
        }

        PPush.allow_reconnect = true;
        PPush.debug('Connecting', url);

        var self = this;

        if (window["WebSocket"]) {
            var ws = new WebSocket(url);

            // Timeout for the connection to handle silently hanging connections
            // Increase the timeout after each retry in case of extreme latencies
            var timeout = PPush.connection_timeout + (self.retry_counter * 500);
            var connectionTimeout = window.setTimeout(function() {
                PPush.debug('Connection timeout after', timeout + 'ms');
                ws.close();
            }, timeout);

            ws.onmessage = function() {
                self.onmessage.apply(self, arguments);
            };
            ws.onclose = function() {
                window.clearTimeout(connectionTimeout);
                self.onclose.apply(self, arguments);
            };
            ws.onopen = function() {
                window.clearTimeout(connectionTimeout);
                self.onopen.apply(self, arguments);
            };

            this.connection = ws;
        } else {
            // Mock connection object if WebSockets are not available.
            this.connection = {};
            setTimeout(function() {
                self.send_local_event("pusher:connection_failed", {})
            }, 0);
        }
    },

    toggle_secure: function() {
        if (this.secure == false) {
            this.secure = true;
            PPush.debug("Switching to wss:// connection");
        } else {
            this.secure = false;
            PPush.debug("Switching to ws:// connection");
        };
    },


    disconnect: function() {
        PPush.debug('Disconnecting');
        PPush.allow_reconnect = false;
        this.retry_counter = 0;
        this.connection.close();
    },

    bind: function(event_name, callback) {
        this.global_channel.bind(event_name, callback)
        return this;
    },

    bind_all: function(callback) {
        this.global_channel.bind_all(callback)
        return this;
    },

    subscribeAll: function() {
        for (var channel in this.channels.channels) {
            if (this.channels.channels.hasOwnProperty(channel)) this.subscribe(channel);
        }
    },

    subscribe: function(channel_name) {
        var channel = this.channels.add(channel_name, this);
        if (this.connected) {
            this.send_event('pusher:subscribe', {
                channel: channel_name,
                channel_data: data.channel_data
            });
        }
        return channel;
    },

    unsubscribe: function(channel_name) {
        this.channels.remove(channel_name);

        if (this.connected) {
            this.send_event('pusher:unsubscribe', {
                channel: channel_name
            });
        }
    },

    send: function(event_name, data) {

        PPush.debug("Sent (event,data)", event_name, data);

        var payload = {

            'header': {
                event: event_name,
                'id': this.id
            },
            'data': data,
        };

        this.connection.send(JSON.stringify(payload));
    },

    send_event: function(header, data, channel) {

        PPush.debug("Event sent (header, data, [channel])", header.event, data, channel);

        if (channel) {
            header['channel'] = channel
        };

        var payload = {
            header: header,
            data: data
        };

        this.connection.send(JSON.stringify(payload));
        return this;
    },

    send_local_event: function(event_header, event_data, channel_name) {
        
        if (channel_name) {
            var channel = this.channel(channel_name);
            if (channel) {
                channel.dispatch_with_all(event_header, event_data);
            }
        } else {
            // Bit hacky but these events won't get logged otherwise
            PPush.debug("Event recd (event,data)", event_header.event, event_data);
        }

        this.global_channel.dispatch_with_all(event_header, event_data);
    },

    onmessage: function(evt) {

        PPush.debug("Retrieve " + evt.data);

        try {

            var params = JSON.parse(evt.data);
            if (params.header.id && params.header.id == this.id) return;
            this.send_local_event(params.header, params.data);

        } catch (e) {

            //console.dir(e);
        }
    },

    reconnect: function() {
        var self = this;
        setTimeout(function() {
            self.connect();
        }, 0);
    },

    retry_connect: function() {
        // Unless we're ssl only, try toggling between ws & wss
        if (!this.encrypted) {
            this.toggle_secure();
        }

        // Retry with increasing delay, with a maximum interval oPPushs
        var retry_delay = Math.min(this.retry_counter * 250, 10000);
        PPush.debug("Retrying connection in " + retry_delay + "ms");
        var self = this;
        setTimeout(function() {
            self.connect();
        }, retry_delay);

        this.retry_counter = this.retry_counter + 1;
    },

    onclose: function() {
        this.global_channel.dispatch('close', null);
        PPush.debug("Socket closed")
        if (this.connected) {
            this.send_local_event("pusher:connection_disconnected", {});
            if (PPush.allow_reconnect) {
                PPush.debug('Connection broken, trying to reconnect');
                this.reconnect();
            }
        } else {
            this.send_local_event("pusher:connection_failed", {});
            this.retry_connect();
        }
        this.connected = false;
    },

    onopen: function() {
        this.global_channel.dispatch('open', null);
    }
};

PPush.Util = {
    extend: function extend(target, extensions) {
        for (var property in extensions) {
            if (extensions[property] && extensions[property].constructor && extensions[property].constructor === Object) {
                target[property] = extend(target[property] || {}, extensions[property]);
            } else {
                target[property] = extensions[property];
            }
        }
        return target;
    }
};

// To receive log output provide a PPush.log function, for example
// PPush.log = function(m){console.log(m)}
PPush.debug = function() {
    if (!PPush.log) {
        return
    }
    var m = ["PPush"]
    for (var i = 0; i < arguments.length; i++) {
        if (typeof arguments[i] === "string") {
            m.push(arguments[i])
        } else {
            m.push(JSON.stringify(arguments[i]))
        }
    };
    PPush.log(m.join(" : "))
}

// PPush defaults
PPush.VERSION = "1.8.5";
PPush.log = function(m) {
    console.log(m);
};
PPush.host = "192.168.178.200";
PPush.ws_port = 8001;
PPush.wss_port = 443;
PPush.connection_timeout = 5000;
PPush.cdn_http = 'http://dev.nacworld.net:8000/static/js'
PPush.cdn_https = 'https://d3ds63zw57jt09.cloudfront.net/'
PPush.allow_reconnect = true;
PPush.parser = function(data) {
    try {
        return JSON.parse(data);
    } catch (e) {
        PPush.debug("Data attribute not valid JSON - you may wish to implement your own PPush.parser");
        return data;
    }
};

PPush.isReady = false;
PPush.ready = function() {
    PPush.isReady = true;
    for (var i = 0; i < PPush.instances.length; i++) {
        if (!PPush.instances[i].connected) PPush.instances[i].connect();
    }
}


PPush.Channels = function() {
    this.channels = {};
};

PPush.Channels.prototype = {
    add: function(channel_name, pusher) {
        var existing_channel = this.find(channel_name);
        if (!existing_channel) {
            var channel = PPush.Channel.factory(channel_name, pusher);
            this.channels[channel_name] = channel;
            return channel;
        } else {
            return existing_channel;
        }
    },

    find: function(channel_name) {
        return this.channels[channel_name];
    },

    remove: function(channel_name) {
        delete this.channels[channel_name];
    }
};

PPush.Channel = function(channel_name, pusher) {
    this.pusher = pusher;
    this.name = channel_name;
    this.callbacks = {};
    this.global_callbacks = [];
    this.subscribed = false;
};

PPush.Channel.prototype = {
    // inheritable constructor
    init: function() {

    },

    disconnect: function() {

    },

    // Activate after successful subscription. Called on top-level pusher:subscription_succeeded
    acknowledge_subscription: function(data) {
        this.subscribed = true;
    },

    bind: function(event_name, callback) {
        this.callbacks[event_name] = this.callbacks[event_name] || [];
        this.callbacks[event_name].push(callback);
        return this;
    },

    bind_all: function(callback) {
        this.global_callbacks.push(callback);
        return this;
    },

    trigger: function(event_name, data) {
        this.pusher.send_event(event_name, data, this.name);
        return this;
    },

    dispatch_with_all: function(header, data) {
        if (this.name != 'pusher_global_channel') {
            PPush.debug("Event recd (channel,event,data)", this.name, header.event_name, data);
        }
        this.dispatch(header, data);
        this.dispatch_global_callbacks(header, data);
    },

    dispatch: function(event_header, event_data) {
        var callbacks = this.callbacks[event_header.event];

        if (callbacks) {
            for (var i = 0; i < callbacks.length; i++) {
                callbacks[i](event_data);
            }
        } else if (!this.global) {
            PPush.debug('No callbacks for ' + event_header.event);
        }
    },

    dispatch_global_callbacks: function(event_header, event_data) {
        for (var i = 0; i < this.global_callbacks.length; i++) {
            this.global_callbacks[i](event_header, event_data);
        }
    },

    is_private: function() {
        return false;
    },

    is_presence: function() {
        return false;
    },
};


PPush.Channel.PresenceChannel = {

    init: function() {
        this.bind('pusher_internal:subscription_succeeded', function(sub_data) {
            this.acknowledge_subscription(sub_data);
            this.dispatch_with_all('pusher:subscription_succeeded', this.members);
        }.scopedTo(this));

        this.bind('pusher_internal:member_added', function(data) {
            var member = this.members.add(data.user_id, data.user_info);
            this.dispatch_with_all('pusher:member_added', member);
        }.scopedTo(this))

        this.bind('pusher_internal:member_removed', function(data) {
            var member = this.members.remove(data.user_id);
            if (member) {
                this.dispatch_with_all('pusher:member_removed', member);
            }
        }.scopedTo(this))
    },

    disconnect: function() {
        this.members.clear();
    },

    acknowledge_subscription: function(sub_data) {
        this.members._members_map = sub_data.presence.hash;
        this.members.count = sub_data.presence.count;
        this.subscribed = true;
    },

    is_presence: function() {
        return true;
    },

    members: {
        _members_map: {},
        count: 0,

        each: function(callback) {
            for (var i in this._members_map) {
                callback({
                    id: i,
                    info: this._members_map[i]
                });
            }
        },

        add: function(id, info) {
            this._members_map[id] = info;
            this.count++;
            return this.get(id);
        },

        remove: function(user_id) {
            var member = this.get(user_id);
            if (member) {
                delete this._members_map[user_id];
                this.count--;
            }
            return member;
        },

        get: function(user_id) {
            var user_info = this._members_map[user_id];
            if (user_info) {
                return {
                    id: user_id,
                    info: user_info
                }
            } else {
                return null;
            }
        },

        clear: function() {
            this._members_map = {};
            this.count = 0;
        }
    }
};

PPush.Channel.factory = function(channel_name, pusher) {
    var channel = new PPush.Channel(channel_name, pusher);
    if (channel_name.indexOf(PPush.Channel.private_prefix) === 0) {
        PPush.Util.extend(channel, PPush.Channel.PrivateChannel);
    } else if (channel_name.indexOf(PPush.Channel.presence_prefix) === 0) {
        PPush.Util.extend(channel, PPush.Channel.PrivateChannel);
        PPush.Util.extend(channel, PPush.Channel.PresenceChannel);
    };
    channel.init(); // inheritable constructor
    return channel;
};

PPush.Channel.private_prefix = "private-";
PPush.Channel.presence_prefix = "presence-";

var _require = (function() {

    var handleScriptLoaded;
    if (document.addEventListener) {
        handleScriptLoaded = function(elem, callback) {
            elem.addEventListener('load', callback, false)
        }
    } else {
        handleScriptLoaded = function(elem, callback) {
            elem.attachEvent('onreadystatechange', function() {
                if (elem.readyState == 'loaded' || elem.readyState == 'complete') callback()
            })
        }
    }

    return function(deps, callback) {
        var dep_count = 0,
            dep_length = deps.length;

        function checkReady(callback) {
            dep_count++;
            if (dep_length == dep_count) {
                // Opera needs the timeout for page initialization weirdness
                setTimeout(callback, 0);
            }
        }

        function addScript(src, callback) {
            callback = callback ||
            function() {}
            var head = document.getElementsByTagName('head')[0];
            var script = document.createElement('script');
            script.setAttribute('src', src);
            script.setAttribute("type", "text/javascript");
            script.setAttribute('async', true);

            handleScriptLoaded(script, function() {
                checkReady(callback);
            });

            head.appendChild(script);
        }

        for (var i = 0; i < dep_length; i++) {
            addScript(deps[i], callback);
        }
    }
})();

;
(function() {
    var cdn = (document.location.protocol == 'http:') ? PPush.cdn_http : PPush.cdn_https;
    var root = cdn;

    var deps = [];
    if (window['JSON'] == undefined) {
        deps.push(root + '/json2.js');
    }
    if (window['WebSocket'] == undefined) {
        // We manually initialize web-socket-js to iron out cross browser issues
        window.WEB_SOCKET_DISABLE_AUTO_INITIALIZATION = true;
        deps.push(root + '/flashfallback.js');
    }

    var initialize = function() {
        if (window['WebSocket'] == undefined) {
            return function() {
                // This runs after flashfallback.js has loaded
                if (window['WebSocket']) {
                    window.WEB_SOCKET_SWF_LOCATION = root + "/WebSocketMain.swf";
                    WebSocket.__addTask(function() {
                        PPush.ready();
                    })
                    WebSocket.__initialize();
                } else {
                    // Flash must not be installed
                    PPush.debug("Could not connect: WebSocket is not available natively or via Flash");
                    // TODO: Update PPush state in such a way that users can bind to it
                }
            }
        } else {
            return function() {
                PPush.ready();
            }
        }
    }();

    var ondocumentbody = function(callback) {
        var load_body = function() {
            document.body ? callback() : setTimeout(load_body, 0);
        }
        load_body();
    };

    var initializeOnDocumentBody = function() {
        ondocumentbody(initialize);
    }

    if (deps.length > 0) {
        _require(deps, initializeOnDocumentBody);
    } else {
        initializeOnDocumentBody();
    }
})();

