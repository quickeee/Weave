/* ***** BEGIN LICENSE BLOCK *****
 *
 * This file is part of Weave.
 *
 * The Initial Developer of Weave is the Institute for Visualization
 * and Perception Research at the University of Massachusetts Lowell.
 * Portions created by the Initial Developer are Copyright (C) 2008-2015
 * the Initial Developer. All Rights Reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 * 
 * ***** END LICENSE BLOCK ***** */

package weave.services
{
	import flash.net.URLLoaderDataFormat;
	
	import mx.rpc.AsyncToken;
	import mx.rpc.events.ResultEvent;
	
	import weave.api.reportError;

	public class WFSServlet extends Servlet
	{
		public function WFSServlet(wfsURL:String, useURLsInGetCapabilities:Boolean, version:String="1.1.0")
		{
			super(wfsURL, "request", URLLoaderDataFormat.VARIABLES);

			this.version = version;
			this.url_getCapabilities = wfsURL;
			this.url_describeFeatureType = wfsURL;
			this.url_getFeature = wfsURL;
			
			if (useURLsInGetCapabilities)
				invokeLater = true;
		}
		
		public var version:String;
		
		private var url_getCapabilities:String;
		private var url_describeFeatureType:String;
		private var url_getFeature:String;
		
		private var delayedInvocations:Array = [];
		
		override public function invokeAsyncMethod(methodName:String, methodParameters:Object = null):AsyncToken
		{
			if (!methodParameters)
				methodParameters = {};
			methodParameters.version = version;
			methodParameters.service = 'WFS';
			return super.invokeAsyncMethod(methodName, methodParameters);
		}
		
		public function getCapabilties():AsyncToken
		{
			_getCapabilitiesCalled = true;
			
			var token:AsyncToken = invokeAsyncMethod("getCapabilities");
			
			if (invokeLater)
			{
				addAsyncResponder(token, handleGetCapabilities, handleGetCapabilitiesFault);
				invokeNow(token); // invoke getCapabilities immediately
			}
			
			return token;
		}
		
		private var _getCapabilitiesCalled:Boolean = false;
		
		private function handleGetCapabilities(event:ResultEvent, token:Object=null):void
		{
			var owsNS:String = 'http://www.opengis.net/ows';
			var xlinkNS:String = 'http://www.w3.org/1999/xlink';
			var xml:XML;
			try
			{
				xml = XML(event.result);
				var operations:XMLList = xml.descendants(new QName(owsNS, 'Operation'));
				var owsGet:QName = new QName(owsNS, 'Get');
				var xlinkHref:QName = new QName(xlinkNS, 'href');
				url_describeFeatureType = operations.(@name == "DescribeFeatureType").descendants(owsGet).attribute(xlinkHref);
				url_getFeature = operations.(@name == "GetFeature").descendants(owsGet).attribute(xlinkHref);
			}
			catch (e:Error)
			{
				reportError("Unable to parse GetCapabilities response.");
				
				if (xml)
					trace(xml.toXMLString());
			}
			
			invokeLater = false; // resume all delayed url requests 
		}
		private function handleGetCapabilitiesFault(..._):void
		{
			// assume the urls for these methods are the same as the one that just failed
			invokeLater = false; // resume all delayed url requests
		}
		
		override protected function getServletURLForMethod(methodName:String):String
		{
			if (methodName == 'GetCapabilities')
				return url_getCapabilities;
			if (methodName == 'GetFeature')
				return url_getFeature;
			if (methodName == 'DescribeFeatureType')
				return url_describeFeatureType;
			return _servletURL;
		}
		
		public function describeFeatureType(layerName:String):AsyncToken
		{
			if (!_getCapabilitiesCalled)
				getCapabilties();
				
			return invokeAsyncMethod("DescribeFeatureType", {typeName: layerName});
		}
		
		public function getFeature(layerName:String, propertyNames:Array = null):AsyncToken
		{
			if (!_getCapabilitiesCalled)
				getCapabilties();
			
			var params:Object = {typeName: layerName};
			if (propertyNames != null && propertyNames.length != 0)
				params.propertyName = propertyNames.join(',');
			
			return invokeAsyncMethod("GetFeature", params);
		}
		
		public function getFilteredQueryResult(layerName:String, propertyNames:Array, filterQuery:String):AsyncToken
		{
			if (!_getCapabilitiesCalled)
				getCapabilties();
			
			var params:Object = {typeName: layerName, filter: filterQuery};
			if(propertyNames != null && propertyNames.length != 0)
				params.propertyName = propertyNames.join(',');
			
			return invokeAsyncMethod("GetFeature", params);
		}
		
/*		public function getAttributeColumn(pathInHierarchy:XML):AsyncToken
		{
			var node:XML = HierarchyUtils.getLeafNodeFromPath(pathInHierarchy);
			
			var params:Object = new Object();
			for each (var attr:String in ['dataTable', 'name', 'year', 'min', 'max'])
			{
				var value:String = node.attribute(attr);
				if (value != '')
					params[attr] = value;
			}
			
			return invokeAsyncMethod("getAttributeColumn", params);
		}
*/		
	}
}

internal class DelayedInvocation
{
	public function DelayedInvocation(func:Function, args:Array)
	{
		this.func = func;
		this.args = args;
	}
	
	private var func:Function;
	private var args:Array;
	
	public function invoke():void
	{
		func.apply(null, args);
	}
}
