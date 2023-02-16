// For documentation on Fiberplane Templates, see: https://docs.fiberplane.com/templates
local fp = import 'fiberplane.libsonnet';
local c = fp.cell;
local fmt = fp.format;

function(
  title= 'argocd',
  status='',
  name='',
  url='',
  operationState='',
  repo ='',
  errormessage = ''
)
  fp.notebook
  .new(title)
  .setTimeRangeRelative(minutes=15)
  .addLabels({
    'service': name,
    'status': status
  })
  .setDataSourceForProviderType('prometheus', 'data-source-name', 'proxy-name') // <------ add here your datasource configuration
  .addCells([
    c.text('The sync operation of application ' + name + ' has failed at ' + operationState),
    c.text([fmt.highlight(['Error message: ' + errormessage])]),
    c.text('Sync operation details are available here: ' + url),
    c.text([fmt.underline(['Link to repo: ' + repo])]),
    c.h3('Unhealthy pods'),
    c.provider(
      title='',
      intent='prometheus,timeseries',
      queryData='application/x-www-form-urlencoded,query=min_over_time%28sum+by+%28namespace%2C+pod%29+%28kube_pod_status_phase%7Bphase%3D%7E%22Pending%7CUnknown%7CFailed%22%7D%29%5B15m%3A1m%5D%29+%3E+0',
     ),
    ])
