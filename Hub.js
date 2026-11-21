.pragma library

var service = null
var listeners = []

function notify() {
  var current = listeners.slice()
  for (var i = 0; i < current.length; i++) current[i](service)
}

function publish(instance) {
  service = instance
  notify()
}

function retract(instance) {
  if (service !== instance) return
  service = null
  notify()
}

function subscribe(listener) {
  listeners.push(listener)
  listener(service)
}

function unsubscribe(listener) {
  var index = listeners.indexOf(listener)
  if (index >= 0) listeners.splice(index, 1)
}
