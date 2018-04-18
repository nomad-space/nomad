"use strict";
/**
 * Created by Bogdan Medvedev on 30.01.18.
 */
const Promise = require("bluebird");
const config = require('../../modules/config');
const db = require('../db');

const authController = require('./auth.js');
const error = require('../error/api.js');
const fs = require('fs');
const random = require('../random');
let API;
let redis = require('redis').createClient(config.get('redis:port'), config.get('redis:host'));

redis.publishAPI = (method, user, data) => {
    redis.publish('api_notify', JSON.stringify({method, user, data}));
};

function stringToRGBHash(str) { // java String#hashCode
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        hash = str.charCodeAt(i) + ((hash << 5) - hash);
    }
    let c = (hash & 0x00FFFFFF)
        .toString(16)
        .toUpperCase();

    return "00000".substring(0, 6 - c.length) + c;
}

const ethplorer = require('./proxy/ethplorer');

let iconsClass = {
    login: 'uk-icon-sign-in',
    logout: 'uk-icon-sign-out',
    setting: 'uk-icon-cog',
    config: 'uk-icon-cog',
    list: 'uk-icon-list',
    avatar: 'uk-icon-photo',
    friend: 'uk-icon-street-view',
    dialog: 'uk-icon-comments',
    message: 'uk-icon-comment',
    count: 'uk-icon-sort-numeric-desc',
    teacher: 'uk-icon-users',
    education: 'uk-icon-graduation-cap',
    skill: 'uk-icon-book',
    video: 'uk-icon-video-camera',
    seach: 'uk-icon-seach',
    language: 'uk-icon-language',
    pay: 'uk-icon-credit-card',
    favorite: 'uk-icon-star',
    diploma: 'uk-icon-picture-o',
    auth: 'uk-icon-unlock',
    read: 'uk-icon-eye',
    token: 'uk-icon-key',
    mark: 'uk-icon-thumb-tack',
    redis: 'uk-icon-database',
    event: 'uk-icon-calendar',
    test: 'uk-icon-code',
    user: 'uk-icon-user',
    update: 'uk-icon-pencil',
    upload: 'uk-icon-upload',
    default: 'uk-icon-exclamation-triangle'

};
let controller = {};
API = {
    saveLog(name, err, user, param, json, type, request_id) {
        return new db.logsAPI({
            method: name,
            param: {url: JSON.stringify(param)},
            response: json,
            error: err,
            request_id: request_id,
            user: {
                paramConnect: user.paramConnect,
            },
            latency_ms: json.latency_ms,
            type_req: type
        }).save();
        // console.log('API log:', name, err, param, json, type, request_id);

    },
    register: (name, _public, cb, docs) => {
        if (typeof _public == 'function') {
            docs = cb;
            cb = _public;
            _public = false
        }

        if (_public) name = 'public_' + name;
        if (!controller[name]) controller[name] = {};
        controller[name].fn = cb;
        controller[name].level = docs.level;
        if (_public)
            controller[name].level = 0;
        if (!docs.level && docs.level !== 0)
            controller[name].level = 3;

        if (docs && !docs.hide) {
            docs.method = name;
            docs.iconColor = stringToRGBHash(name);
            for (let index in iconsClass) {
                if (name.toLowerCase().indexOf(index) !== -1) {
                    docs.iconClass = iconsClass[index];
                    break;
                }
            }
            if (!docs.iconClass)
                docs.iconClass = iconsClass.default;
            if (_public)
                docs.access = 1;
            else
                docs.access = 2;
            if (!docs.level) {
                if (_public)
                    docs.level = 0;
                else
                    docs.level = 1;
            }
            if (docs.response) {
                docs.response.unshift({
                        name: 'success',
                        type: "string",
                        title: 'Status request method',
                        default: 'true, false'
                    },
                    {
                        name: 'error',
                        type: "object",
                        title: 'Error data.(exists only in cases of error)',
                        default: '{message,error_type,level,stack}'
                    },
                    {
                        name: 'data',
                        type: "object",
                        title: 'Result data.',
                        default: '{}'
                    });
                docs.response.push({
                    name: 'latency_ms',
                    type: "int",
                    title: 'processing time of the request (milliseconds)',
                    default: '78'
                });
            }
            docs.code = cb.toString().replace('(user, param) => {', '').replace(new RegExp('\n    }', 'g'), '').replace(new RegExp('\n        ', 'g'), '\n');
            setTimeout(function () {
                let add = true;
                for (let index in API.docs) {
                    if (API.docs[index].method === docs.method) {

                        API.docs[index] = docs;
                        add = false;
                    }
                }
                if (add) API.docs.push(docs);
            }, 1)
        }
    },
    call: (name, user, param, type) => {
        let initTimestamp = (new Date()).getTime(); // start time unix call method

        let request_id = new Date().getTime() + '-' + random.str(7, 7); // reqid for login and response

        if (!type) type = 'server';
        // console.log('emit api', {name, type});
        if (!param) param = {};
        return new Promise((resolve, reject) => {
            if (!name || !controller.hasOwnProperty(name))
                return reject(error.create('method not fount', 'api', {
                    method_find: name,
                }, 0, 40400, 404));
            resolve();
        })

        // authorization controller ------------>
            .then(() => {
                // auth data
                return Promise.props({
                    user: authController.user(user),
                    admin: authController.admin(user)
                }).catch(err => {
                    console.error('Error authorization init', err);
                    return Promise.reject(err);
                })

            })
            .then(auth => {
                // check user
                return authController.checkAuth(controller[name].level, auth).catch(err => {
                    console.error('Error authorization checkAuth', err);
                    return Promise.reject(err);
                })
            })
            .then(auth => {
                // user add auth
                user.admin = auth.admin;
                user.user = auth.user;
            })
            // ---^^^^^---  authorization controller ---^^^^^^----

            //
            .then(() => {
                if (controller[name].level === 3 && type !== 'server')
                    return Promise.reject(error.create('This method can not be used for REST-API', 'forbidden', {
                        pos: 'modules/api/index.js(controller):#3',
                        level: controller[name].level
                    }, 'server', 0, 40304, 403));
                return true;
            })
            .then(() => {
                // function
                return controller[name].fn(user, param)
            })
            .then((json) => {
                // save success log
                API.saveLog(name, null, user, param, json, type, request_id);
                return json
            })
            .then((json) => {
                if (!json)
                    return Promise.reject('CORE API error {res} of undefined');
                let res = {success: true, data: json};
                res.latency_ms = (new Date()).getTime() - initTimestamp;
                res.requestId = request_id;
                return res;
            })
            // timeout promise
            .timeout(1000 * config.get('server:api:timeout'), 'API timeout')
            // ----- Error API ---------->
            .catch(err => {
                console.error(err);

                // error save log
                // if (!err || err.level > 1) console.error('API->emit(name, user, param, cb, type)->controller[name]->err:', err);
                API.saveLog(name, null, user, param, {success: false, result: false}, type, request_id);
                return Promise.reject(err);

            })
            .catch(err => {
                // error transfer api
                if (err.apiError)
                    return Promise.reject(err);


                // error is not api data error
                console.error(err);
                let err_message = 'no_message';
                if (err && typeof err === 'string') err_message = 'REST-API Error: ' + err;
                if (err && err.message && typeof err.message === 'string') err_message = 'REST-API Error: ' + err.message;
                return Promise.reject(error.create('REST-API Error: ' + err_message, 'api', {
                    pos: 'modules/api/index.js(controller):#200',
                    param: param,
                    level: controller[name].level,
                    type: 'api'
                }, 0, 500));
            })

            .catch(err => {
                let res = {success: false, error: err};
                res.latency_ms = (new Date()).getTime() - initTimestamp;
                res.requestId = request_id;

                return Promise.reject(res);
            }); // ---^^^^^---  Error API  ---^^^^^^----


    },
    docs: [], config:
        {
            secure: {
                http: 'HGUYFG8-4FeESmF75a-Rc2J80YJ3z-UM28pPJ07',
                api_server_key:
                    'o40445Qm-4FeESmF75a-Rc2J80YJ3z-6fwgGd',
            }

        },
    proxy: {
        ethplorer: ethplorer
    },
    error: error,
    cache: {}
};
// alias method
API.emit = API.call;
API.on = API.register;
let API_cnt = 0;

function requireAPI(apiPath) {
    // console.log("API:" + apiPath);
    API_cnt++;
    let fileAPI = require('../../../api/' + apiPath);
    if (typeof fileAPI === 'function')
        fileAPI(API, redis);
    else
        console.error('[Error] (api/' + apiPath + ') Function is not defined:  \n\t' + '\n' +
            'module.exports = (API, redis) => {};\n')
}

fs.readdir('./api', (err, items) => {
    for (let i = 0; i < items.length; i++) {
        if (fs.statSync('./api/' + items[i]).isDirectory())
            fs.readdir('./api/' + items[i], (err, items2) => {
                for (let i2 = 0; i2 < items2.length; i2++) {
                    if (!fs.statSync('./api/' + items[i] + '/' + items2[i2]).isDirectory())
                        requireAPI(items[i] + '/' + items2[i2]);
                    else
                        console.error("API Error load:" + items[i] + '/' + items2[i2]);

                }
            });
        else
            requireAPI(items[i]);
    }

    // export_postman docs file
    setTimeout(require('./export_postman'), 3000);
    setTimeout(require('./export_insomnia'), 3000);
    setTimeout(function () {
        console.log("API running: " + API_cnt + " files\n\t Docs " + config.get('shema') + '://' + config.get('domain') + config.get('server_path') + config.get('api_path') + 'docs/')
    }, 3000);
});
module.exports.controller = controller;
module.exports.API = API;