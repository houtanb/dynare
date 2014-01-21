function o = writeLine(o, fid, xrange)
%function o = writeLine(o, fid, xrange)
% Print a TikZ line
%
% INPUTS
%   o       [report_series]    series object
%   xrange  [dates]            range of x values for line
%
% OUTPUTS
%   NONE
%
% SPECIAL REQUIREMENTS
%   none

% Copyright (C) 2014 Dynare Team
%
% This file is part of Dynare.
%
% Dynare is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Dynare is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Dynare.  If not, see <http://www.gnu.org/licenses/>.

%% Validate options provided by user
assert(~isempty(o.data) && isa(o.data, 'dseries'), ['@report_series.writeLine: must ' ...
                    'provide data as a dseries']);

% Line
assert(ischar(o.graphLineColor), '@report_series.writeLine: graphLineColor must be a string');
assert(ischar(o.graphLineStyle), '@report_series.writeLine: graphLineStyle must be a string');
assert(ischar(o.graphLineWidth), '@report_series.writeLine: graphLineWidth must be a string');

% GraphMarker
valid_graphMarker = {'+', 'o', '*', '.', 'x', 's', 'square', 'd', 'diamond', ...
                '^', 'v', '>', '<', 'p', 'pentagram', 'h', 'hexagram', ...
                'none'};
assert(isempty(o.graphMarker) || any(strcmp(o.graphMarker, valid_graphMarker)), ...
       ['@report_series.writeLine: graphMarker must be one of ' strjoin(valid_graphMarker)]);

assert(ischar(o.graphMarkerEdgeColor), '@report_series.writeLine: graphMarkerEdgeColor must be a string');
assert(ischar(o.graphMarkerFaceColor), '@report_series.writeLine: graphMarkerFaceColor must be a string');
assert(isfloat(o.graphMarkerSize), ['@report_series.writeLine: graphMarkerSize must be a ' ...
                    'positive number']);

% Marker & Line
assert(~(strcmp(o.graphLineStyle, 'none') && isempty(o.graphMarker)), ['@report_series.writeLine: ' ...
                    'you must provide at least one of graphLineStyle and graphMarker']);

% Validate xrange
assert(isempty(xrange) || isa(xrange, 'dates'));

% Zero tolerance
assert(isfloat(o.zerotol), '@report_series.write: zerotol must be a float');

%%
if isempty(xrange) || all(xrange == o.data.dates)
    ds = o.data;
else
    ds = o.data(xrange);
end

% if graphing data that is within zerotol, set to zero, create report_series and
% get line:
thedata = ds.data;
stz = bsxfun(@and, ...
             bsxfun(@lt, thedata, o.zerotol), ...
             bsxfun(@gt, thedata, -o.zerotol));
if any(stz)
    thedata(stz) = 0;
end

fprintf(fid, '\\draw[%s, %s, %s] ', o.graphLineStyle, o.graphLineWidth, o.graphLineColor);
ndat = ds.dates.ndat;
for i=1:ndat
    fprintf(fid, '(%d, %f)', i, thedata(i));
    if i ~= ndat
        fprintf(fid, '--');
    end
end
fprintf(fid, ';\n');


%opt = {'XData', 1:length(thedata)};

if ~isempty(o.graphMarker)
    %opt = {opt{:}, 'Marker', o.graphMarker};
    %opt = {opt{:}, 'MarkerSize', o.graphMarkerSize};
    %opt = {opt{:}, 'MarkerEdgeColor', o.graphMarkerEdgeColor};
    %opt = {opt{:}, 'MarkerFaceColor', o.graphMarkerFaceColor};
end
end
