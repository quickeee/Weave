/**
 * 
 */
var bioWeave_mod = angular.module('aws.bioWeave', []);

bioWeave_mod.controller("BioWeaveController", function($scope,algorithmObjectService){

});

bioWeave_mod.controller('AlgoObjectListController', function($scope,algorithmObjectService ){
	$scope.algorithmObjectService = algorithmObjectService;
	
	//retrieve list of algorithm Objects
	algorithmObjectService.getListOfAlgoObjects();
	
});

bioWeave_mod.controller('InputParamsController', function($scope, algorithmObjectService, runScriptService){
	//pulls in the external template for use in ng-include in the main BioWeaveManager.html
	$scope.inputParamsHTMLTpl = {url: 'aws/bioWeave/parameterInputPanel.html'};
	
	$scope.algorithmObjectService = algorithmObjectService;
	
	$scope.collectAlgoObjects = function(){
		var titles = [];
		
		for(var f in algorithmObjectService.data.algorithmMetadataObjects){
			titles[f] = algorithmObjectService.data.algorithmMetadataObjects[f].title;
		}
		algorithmObjectService.getScripts(titles);
		//runScriptService.runScript(algorithmObjectService.data.currentMetObj);
	};
	
});

bioWeave_mod.controller('ResultsViewController', function($scope, algorithmObjectService){
	//pulls in the external template for use in ng-include in the main BioWeaveManager.html
	$scope.resultViewHTMLTpl = {url: 'aws/bioWeave/resultViewPanel.html'};
	
	$scope.algorithmObjectService = algorithmObjectService;
});