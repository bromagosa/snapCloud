-- CORS module
-- ==========
--
-- A list of whitelisted domains that we support.
--
-- Written by Bernat Romagosa
--
-- Copyright (C) 2018 by Bernat Romagosa
--
-- This file is part of Snap Cloud.
--
-- Snap Cloud is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as
-- published by the Free Software Foundation, either version 3 of
-- the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

local domain_allowed = {}
domain_allowed['snap.berkeley.edu'] = true
domain_allowed['amazingrobots.net'] = true
domain_allowed['snap4arduino.rocks'] = true
-- This domain serves an HTTP only Snap! IDE
domain_allowed['extensions.snap.berkeley.edu'] = true
-- Snap4Arduino for Chromebooks
domain_allowed['chrome-extension://bdmapaboflkhdmcgdpfooeeeadejodia'] = true
-- App Server Domains
-- By Default CORS is not needed on the same domain.
-- However, we want to allow access on http hosted versions of Snap!.
domain_allowed['snap-cloud.cs10.org'] = true
domain_allowed['cloud.snap.berkeley.edu'] = true
-- App Server Staging Domains
domain_allowed['snap-staging.cs10.org'] = true
domain_allowed['staging.snap.berkeley.edu'] = true
-- Snap! Mirrors
domain_allowed['cs10.org'] = true
domain_allowed['bjc.edc.org'] = true
domain_allowed['web.media.mit.edu'] = true
-- Snap! Research Projects
domain_allowed['eliza.csc.ncsu.edu'] = true
domain_allowed['arena.csc.ncsu.edu'] = true
domain_allowed['stemc.csc.ncsu.edu'] = true
domain_allowed['lambda.cs10.org'] = true
-- All edX Sites, and test sites
domain_allowed['courses.edge.edx.org'] = true
domain_allowed['courses.edx.org'] = true
domain_allowed['d37djvu3ytnwxt.cloudfront.net'] = true
domain_allowed['preview.courses.edge.edx.org'] = true
domain_allowed['preview.courses.edx.org'] = true
domain_allowed['preview.edge.edx.org'] = true
domain_allowed['preview.edx.org'] = true
domain_allowed['studio.edge.edx.org'] = true
domain_allowed['studio.edx.org'] = true
domain_allowed['edge.edx.org'] = true
-- Development
domain_allowed['romagosa.work'] = true
domain_allowed['localhost'] = true

return domain_allowed
