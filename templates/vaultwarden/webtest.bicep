@description('The name of the ping test.')
param name string

@description('Location for the resources.')
param location string = resourceGroup().location

@description('The url you wish to test.')
param pingURL string

@description('The text you would like to find.')
param pingText string = ''

@description('The alert severity.')
@allowed([
  0
  1
  2
  3
  4
])
param severity int = 1

@description('The id of the underlying Application Insights resource.')
param appInsightsResourceId string

@allowed([
  'emea-au-syd-edge'
  'latam-br-gru-edge'
  'us-fl-mia-edge'
  'apac-hk-hkn-azr'
  'us-va-ash-azr'
  'emea-ch-zrh-edge'
  'emea-fr-pra-edge'
  'apac-jp-kaw-edge'
  'emea-gb-db3-azr'
  'us-il-ch1-azr'
  'us-tx-sn1-azr'
  'apac-sg-sin-azr'
  'emea-se-sto-edge'
  'emea-nl-ams-azr'
  'us-ca-sjc-azr'
  'emea-ru-msa-edge'
])
@description('The locations for the webtest.')
param webtestLocations array = [
  'emea-nl-ams-azr'
  'emea-gb-db3-azr'
  'us-ca-sjc-azr'
  'us-va-ash-azr'
  'emea-au-syd-edge'
]

var pingTestName = 'PingTest-${toLower(name)}'
var pingAlertRuleName = 'PingAlert-${toLower(name)}-${subscription().subscriptionId}'

resource pingTest 'Microsoft.Insights/webtests@2015-05-01' = {
  name: pingTestName
  location: location
  tags: {
    'hidden-link:${appInsightsResourceId}': 'Resource'
  }
  properties: {
    Name: pingTestName
    Description: 'Basic ping test'
    Enabled: true
    Frequency: 300
    Timeout: 120
    Kind: 'ping'
    RetryEnabled: true
    Locations: [for webtestLocation in webtestLocations: {
      Id: webtestLocation
    }]
    Configuration: {
      WebTest: '<WebTest   Name="${pingTestName}"   Enabled="True"         CssProjectStructure=""    CssIteration=""  Timeout="120"  WorkItemIds=""         xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"         Description=""  CredentialUserName=""  CredentialPassword=""         PreAuthenticate="True"  Proxy="default"  StopOnError="False"         RecordedResultFile=""  ResultsLocale="">  <Items>  <Request Method="GET"    Version="1.1"  Url="${pingURL}" ThinkTime="0"  Timeout="300" ParseDependentRequests="True"         FollowRedirects="True" RecordResult="True" Cache="False"         ResponseTimeGoal="0"  Encoding="utf-8"  ExpectedHttpStatusCode="200"         ExpectedResponseUrl="" ReportingName="" IgnoreHttpStatusCode="False" />        </Items>  <ValidationRules> <ValidationRule  Classname="Microsoft.VisualStudio.TestTools.WebTesting.Rules.ValidationRuleFindText, Microsoft.VisualStudio.QualityTools.WebTestFramework, Version=10.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a" DisplayName="Find Text"         Description="Verifies the existence of the specified text in the response."         Level="High"  ExecutionOrder="BeforeDependents">  <RuleParameters>        <RuleParameter Name="FindText" Value="${pingText}" />  <RuleParameter Name="IgnoreCase" Value="False" />  <RuleParameter Name="UseRegularExpression" Value="False" />  <RuleParameter Name="PassIfTextFound" Value="True" />  </RuleParameters> </ValidationRule>  </ValidationRules>  </WebTest>'
    }
    SyntheticMonitorId: pingTestName
  }
}

resource pingAlertRule 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: pingAlertRuleName
  location: 'global'
  tags: {
    'hidden-link:${appInsightsResourceId}': 'Resource'
    'hidden-link:${pingTest.id}': 'Resource'
  }
  properties: {
    description: 'Alert for web test'
    severity: severity
    enabled: true
    scopes: [
      pingTest.id
      appInsightsResourceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
      webTestId: pingTest.id
      componentId: appInsightsResourceId
      failedLocationCount: 2
    }
  }
}
