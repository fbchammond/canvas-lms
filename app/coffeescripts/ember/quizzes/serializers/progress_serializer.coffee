define [ 'ember-data' ], (DS) ->
  DS.ActiveModelSerializer.extend
    extractSingle: (store, type, payload, id, requestType) ->
      @_super store, type, { progress: [ payload ] }, id, requestType